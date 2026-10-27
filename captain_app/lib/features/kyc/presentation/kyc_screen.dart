import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../models/captain_profile.dart';

/// Licence details and document photos. Submitting sends them to the admin team for review;
/// the captain moves on once an admin approves them in the admin console.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final _license = TextEditingController();
  final _address = TextEditingController();
  DateTime? _expiry;
  DateTime? _dob;
  List<KycDocument> _documents = const [];
  String? _uploading;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(onboardingProvider).value?.profile;
    if (profile != null) {
      _license.text = profile.licenseNumber;
      _address.text = profile.address;
      _expiry = DateTime.tryParse(profile.licenseExpiry ?? '');
      _dob = DateTime.tryParse(profile.dateOfBirth ?? '');
    }
    _loadDocuments();
  }

  @override
  void dispose() {
    _license.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final documents = await ref.read(kycRepositoryProvider).documents();
      if (mounted) setState(() => _documents = documents);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  bool _hasDocument(String type) => _documents.any((d) => d.docType == type);

  Future<void> _pickAndUpload(String type) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1800);
    if (picked == null) return;
    setState(() {
      _uploading = type;
      _error = null;
    });
    try {
      await ref.read(kycRepositoryProvider).uploadDocument(docType: type, path: picked.path, filename: picked.name);
      await _loadDocuments();
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (expiry ? _expiry : _dob) ?? (expiry ? now.add(const Duration(days: 365)) : DateTime(now.year - 25)),
      firstDate: expiry ? now : DateTime(now.year - 80),
      lastDate: expiry ? DateTime(now.year + 30) : DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => expiry ? _expiry = picked : _dob = picked);
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_license.text.trim().isEmpty || _expiry == null || _dob == null || _address.text.trim().isEmpty) {
      setState(() => _error = 'Fill in all the details.');
      return;
    }
    if (_documents.isEmpty) {
      setState(() => _error = 'Upload your documents first.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(kycRepositoryProvider).submit(
            licenseNumber: _license.text.trim(),
            licenseExpiry: _iso(_expiry!),
            dateOfBirth: _iso(_dob!),
            address: _address.text.trim(),
          );
      // The status is now UNDER_REVIEW, so the router moves to the review screen.
      await ref.read(onboardingProvider.notifier).refresh();
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(onboardingProvider).value?.profile;
    final rejected = profile?.kycStatus == KycStatus.rejected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your documents'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InfoCard(
                color: AppColors.danger.withValues(alpha: 0.08),
                child: Text(
                  profile!.rejectionReason.isEmpty
                      ? 'Your documents were not approved. Please review and submit again.'
                      : 'Your documents were not approved: ${profile.rejectionReason}',
                ),
              ),
            ),
          TextField(
            controller: _license,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Driving licence number'),
          ),
          const SizedBox(height: 12),
          _DateField(label: 'Licence expiry', value: _expiry, onTap: () => _pickDate(expiry: true)),
          const SizedBox(height: 12),
          _DateField(label: 'Date of birth', value: _dob, onTap: () => _pickDate(expiry: false)),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Home address'),
          ),
          const SizedBox(height: 24),
          Text('Documents', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in kycDocTypes.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _hasDocument(entry.key) ? Icons.check_circle : Icons.upload_file,
                color: _hasDocument(entry.key) ? AppColors.success : AppColors.textSecondary,
              ),
              title: Text(entry.value),
              subtitle: Text(_hasDocument(entry.key) ? 'Uploaded' : 'Not uploaded'),
              trailing: _uploading == entry.key
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _uploading == null ? () => _pickAndUpload(entry.key) : null,
                      child: Text(_hasDocument(entry.key) ? 'Replace' : 'Upload'),
                    ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(label: 'Submit for review', busy: _submitting, onPressed: _submit),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? 'Select date' : '${value!.day}/${value!.month}/${value!.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
        child: Text(text),
      ),
    );
  }
}

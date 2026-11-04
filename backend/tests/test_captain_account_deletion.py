import os

from django.core.files.base import ContentFile

from apps.captains.models import KycDocument
from tests.helpers import make_captain


def test_deleting_a_captain_removes_kyc_document_files_and_records(db, api, settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    captain = make_captain(plan=None, online=False)
    document = KycDocument.objects.create(
        captain=captain, doc_type="IDENTITY", file=ContentFile(b"scan", name="id.jpg")
    )
    path = document.file.path
    assert os.path.exists(path)

    api.force_authenticate(user=captain.user)
    response = api.post("/api/v1/auth/delete-account/", {"confirm": True}, format="json")

    assert response.status_code == 204
    assert not os.path.exists(path)
    assert not KycDocument.objects.filter(captain=captain).exists()

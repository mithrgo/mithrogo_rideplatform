enum Flavor { dev, prod }

/// Selected with --dart-define=FLAVOR=prod (defaults to dev).
class Flavors {
  const Flavors._();

  static const String _name = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static Flavor get current => _name == 'prod' ? Flavor.prod : Flavor.dev;

  static bool get isProd => current == Flavor.prod;

  static const String appName = 'MithrGo';

  static String get title => isProd ? appName : '$appName (Dev)';
}

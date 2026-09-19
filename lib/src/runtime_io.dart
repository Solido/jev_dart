import 'dart:io';

bool get isBrowser => false;

String describeRuntime() =>
    'dart/${Platform.version.split(' ').first} ${Platform.operatingSystem}';

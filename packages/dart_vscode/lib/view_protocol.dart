/// The versioned protocol shared by Host Dart and a Flutter View.
///
/// Both runtimes type against this one published library. It is deliberately
/// not copied into Extension Projects: a wire contract that exists in two
/// places is a wire contract that can disagree with itself.
library;

export 'src/view_protocol.dart';

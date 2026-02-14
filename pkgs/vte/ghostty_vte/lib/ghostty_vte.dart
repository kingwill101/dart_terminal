/// Public entrypoint for ghostty_vte bindings.
///
/// Re-exports the native or web implementation depending on target, giving
/// consumers a single import for all platform variants.
library;

/// Platform-resolved VT parser and emitter API.
///
/// On native targets this exports the FFI-backed implementation; on web
/// targets it exports the wasm/JS-interop variant.
export 'src/api_native.dart' if (dart.library.js_interop) 'src/api_web.dart';

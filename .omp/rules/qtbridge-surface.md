---
name: qtbridge-surface
description: "Keep Swift↔QML declarations visible, owned, and observable through QtBridge"
scope: "tool:edit(*.swift), tool:write(*.swift), tool:edit(*.qml), tool:write(*.qml)"
---

- A stored member in a `@QtBridgeable` class body reaches QML only through an explicitly typed supported type or `@QtTracked`. A non-`private` member with neither is silently invisible: give it a supported type, `@QtTracked`, or `@QtIgnored`.
- The automatically supported property types are `Int`, `UInt`, `Double`, `Float`, `String`, `Bool`, `[String]`/`Array<String>`, `[String: QVariantSettable]`/`Dictionary<String, QVariantSettable>`, `QListModel<…>`, and `QTableModel<…>`. These expose without `@QtTracked`.
- Use `@QtTracked` only when a QML-facing member has a non-supported type, including bridged class references, optionals thereof, and custom value types. Adding it to a supported type changes nothing; a member that carries `@QtTracked` with an inferred type is registered and needs no annotation.
- Mark stored members that must stay invisible to QML with `@QtIgnored`; never put it on `private`/`private(set)` or `static` members, where access already prevents registration. On a non-private computed member it is inert but allowed as documented intent.
- Keep QML-facing state `public`; for controller-only setters, document the ownership at the class instead of using `private(set)`. A `private(set)` declaration does not expose to QML.
- Declare QML-facing members in the class body, not an extension. Extensions are outside QtBridge's registration pass.
- Give QML observers `@QtSignal`s and Swift observers presenter closure hooks; never forward a closure into a second, unobserved signal. Each signal needs a QML handler or Swift subscriber, and each bridged QML signal handler needs an emission path.
- Use only QtBridge-settable primitive, string-list, or map types for `@QtSignal` parameters; consume handler arguments positionally. QtBridge does not register signal parameter names.
- Write slot returns as `Optional<T>` when a returned bridged object can be nil, not `T?`; retain returned objects in Swift for their QML lifetime. Sugar-optional slot returns silently fail registration, and a QML variable retains only the proxy.
- Do not mutate tracked or published state inside `init` of a `QmlInstantiableStatus` class; publish after its holder memoizes the instance. Early emissions cannot reach the holder.
- Equality-gate heavy rebuilt published state with the existing `setPublished`/`matches` pattern. Tracked writes emit without an old/new comparison, and emissions reach QML on the next event-loop turn.
- Make every `src/ui/**/*.qml` file reachable through `qt_add_qml_module` QML_FILES, a Swift `contentUrl`, or a reference from reachable QML. Unreachable files cannot become production surfaces.
- Keep one composition component per surface and point check fixtures at the production file. Copies diverge from the UI they claim to cover.
- Expose Swift objects as registered `PorydawApp` QML elements or through properties and slots from those roots; do not introduce context properties. QML traverses the registered object graph.
- Keep Qt 6 imports versionless, use `Connections { function onX() {} }`, and declare delegate inputs with `required property`. These are the established QML binding conventions.
- Read `model.X` only inside delegates backed by `QListModel`/`QTableModel` of bridged row types. Model roles derive from registered row-property names.

Full normative text and enforcement: `docs/plans/qtbridge-surface/spec.md`; guard: `deno task verify:bridge`.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Owns a QCoreApplication without creating a QML engine or entering an event loop.
typedef struct PdQmlTypesApplication PdQmlTypesApplication;
PdQmlTypesApplication *pd_qmltypes_application_create(int argc, char **argv);
void pd_qmltypes_application_destroy(PdQmlTypesApplication *application);

// Returns QMetaType::UnknownType when the runtime name is not registered.
int pd_qmltypes_metatype_id(const char *name);

// QMetaMethod discriminants from the Qt headers used to build this host.
int pd_qmltypes_method_kind_method(void);
int pd_qmltypes_method_kind_signal(void);
int pd_qmltypes_method_kind_slot(void);
int pd_qmltypes_method_access_public(void);

// Matches QtBridge's element export version 1.0.
int pd_qmltypes_export_revision(void);

#ifdef __cplusplus
}
#endif

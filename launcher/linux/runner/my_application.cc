#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef HAVE_GTK_LAYER_SHELL
#include <gtk-layer-shell.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// The launcher stays resident: the first run opens the window, and running
// it again (from a global shortcut) toggles it. Hiding instead of quitting
// keeps it instant to bring back.

static const int kWidth = 680;
static const int kHeight = 460;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* channel;
  // Start with the window hidden (--hidden, for autostart).
  gboolean start_hidden;
  // Whether the window has had keyboard focus since it was last shown; a
  // focus-out only dismisses a window that had it.
  gboolean had_focus;
  // Pending check after a focus-out, see focus_out_cb.
  guint focus_check;
  // Registration of the dev.flatkit.Launcher D-Bus object.
  guint dbus_object;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void notify_dart(MyApplication* self, const char* method) {
  if (self->channel == nullptr) return;
  fl_method_channel_invoke_method(self->channel, method, nullptr, nullptr, nullptr, nullptr);
}

static void cancel_focus_check(MyApplication* self) {
  if (self->focus_check != 0) {
    g_source_remove(self->focus_check);
    self->focus_check = 0;
  }
}

static void hide_window(MyApplication* self) {
  cancel_focus_check(self);
  if (self->window == nullptr || !gtk_widget_get_visible(GTK_WIDGET(self->window))) return;
  gtk_widget_hide(GTK_WIDGET(self->window));
  self->had_focus = FALSE;
  notify_dart(self, "hidden");
}

static void show_window(MyApplication* self) {
  if (self->window == nullptr) return;
  self->had_focus = FALSE;
  gtk_window_set_position(self->window, GTK_WIN_POS_CENTER_ALWAYS);
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
  GtkWidget* child = gtk_bin_get_child(GTK_BIN(self->window));
  if (child != nullptr) gtk_widget_grab_focus(child);
  notify_dart(self, "shown");
}

static gboolean focus_in_cb(GtkWidget* widget, GdkEvent* event, MyApplication* self) {
  self->had_focus = TRUE;
  cancel_focus_check(self);
  return FALSE;
}

static gboolean focus_check_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->focus_check = 0;
  if (self->window != nullptr && !gtk_window_is_active(self->window)) hide_window(self);
  return G_SOURCE_REMOVE;
}

// Losing focus dismisses the launcher, like clicking away from a menu. Focus
// can blink out and back while the window maps (or a window manager settles
// it), so only hide if it is still gone a moment later.
static gboolean focus_out_cb(GtkWidget* widget, GdkEvent* event, MyApplication* self) {
  if (!self->had_focus || self->focus_check != 0) return FALSE;
  self->focus_check = g_timeout_add(150, focus_check_cb, self);
  return FALSE;
}

// Closing the window (Alt+F4) hides it like Escape does.
static gboolean delete_cb(GtkWidget* widget, GdkEvent* event, MyApplication* self) {
  hide_window(self);
  return TRUE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "hide") == 0) {
    hide_window(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->start_hidden) show_window(self);
}

#ifdef HAVE_GTK_LAYER_SHELL
// On Wayland, a layer-shell overlay is centred by the compositor, sits
// above everything and takes the keyboard, which plain windows can't ask
// for there. FLATKIT_LAUNCHER_NO_LAYER_SHELL=1 turns it off.
static gboolean use_layer_shell() {
  if (g_getenv("FLATKIT_LAUNCHER_NO_LAYER_SHELL") != nullptr) return FALSE;
  return gtk_layer_is_supported();
}
#endif

static void create_window(MyApplication* self) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;

  gtk_window_set_title(window, "Launcher");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_default_size(window, kWidth, kHeight);
  gtk_widget_set_size_request(GTK_WIDGET(window), kWidth, kHeight);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DIALOG);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER_ALWAYS);

#ifdef HAVE_GTK_LAYER_SHELL
  if (use_layer_shell()) {
    gtk_layer_init_for_window(window);
    gtk_layer_set_namespace(window, "flatkit-launcher");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
    // No anchors: the compositor centres the surface.
  }
#endif

  g_signal_connect(window, "focus-in-event", G_CALLBACK(focus_in_cb), self);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(focus_out_cb), self);
  g_signal_connect(window, "delete-event", G_CALLBACK(delete_cb), self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#1c1c1f");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                        "flatkit_launcher/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::activate: the first time it builds the window,
// after that each activation (another `flatkit-launcher` run) toggles it.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) {
    create_window(self);
    // Keep running while hidden.
    g_application_hold(application);
    return;
  }
  if (gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    hide_window(self);
  } else {
    show_window(self);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  gchar** argv = *arguments;

  gboolean hidden = FALSE;
  gboolean quit = FALSE;
  GPtrArray* rest = g_ptr_array_new();
  for (int i = 1; argv[i] != nullptr; i++) {
    if (g_strcmp0(argv[i], "--hidden") == 0) {
      hidden = TRUE;
    } else if (g_strcmp0(argv[i], "--quit") == 0) {
      quit = TRUE;
    } else {
      g_ptr_array_add(rest, g_strdup(argv[i]));
    }
  }
  g_ptr_array_add(rest, nullptr);
  self->dart_entrypoint_arguments = reinterpret_cast<char**>(g_ptr_array_free(rest, FALSE));
  self->start_hidden = hidden;

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (g_application_get_is_remote(application)) {
    // Already running: --quit stops it, --hidden leaves it be, anything
    // else toggles its window.
    if (quit) {
      g_action_group_activate_action(G_ACTION_GROUP(application), "quit", nullptr);
    } else if (!hidden) {
      g_application_activate(application);
    }
  } else if (!quit) {
    g_application_activate(application);
  }
  *exit_status = 0;
  return TRUE;
}

// A D-Bus method with no arguments, so KWin can call it straight from a
// modifier-only shortcut (pressing Meta on its own):
//   kwinrc [ModifierOnlyShortcuts] Meta=dev.flatkit.Launcher,/dev/flatkit/Launcher,dev.flatkit.Launcher,Toggle
// GApplication's own Activate methods take a platform-data argument that
// KWin can't pass.
static const char kIntrospection[] =
    "<node>"
    "  <interface name='dev.flatkit.Launcher'>"
    "    <method name='Toggle'/>"
    "  </interface>"
    "</node>";

static void dbus_method_cb(GDBusConnection* connection, const gchar* sender,
                           const gchar* object_path, const gchar* interface_name,
                           const gchar* method_name, GVariant* parameters,
                           GDBusMethodInvocation* invocation, gpointer user_data) {
  if (g_strcmp0(method_name, "Toggle") == 0) {
    g_application_activate(G_APPLICATION(user_data));
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else {
    g_dbus_method_invocation_return_dbus_error(invocation, "org.freedesktop.DBus.Error.UnknownMethod",
                                               "Unknown method");
  }
}

static const GDBusInterfaceVTable kVtable = {dbus_method_cb, nullptr, nullptr, {nullptr}};

// Implements GApplication::dbus_register.
static gboolean my_application_dbus_register(GApplication* application,
                                             GDBusConnection* connection,
                                             const gchar* object_path, GError** error) {
  MyApplication* self = MY_APPLICATION(application);
  if (!G_APPLICATION_CLASS(my_application_parent_class)
           ->dbus_register(application, connection, object_path, error)) {
    return FALSE;
  }
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(kIntrospection, error);
  if (info == nullptr) return FALSE;
  self->dbus_object = g_dbus_connection_register_object(
      connection, object_path, info->interfaces[0], &kVtable, self, nullptr, error);
  return self->dbus_object != 0;
}

// Implements GApplication::dbus_unregister.
static void my_application_dbus_unregister(GApplication* application,
                                           GDBusConnection* connection,
                                           const gchar* object_path) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->dbus_object != 0) {
    g_dbus_connection_unregister_object(connection, self->dbus_object);
    self->dbus_object = 0;
  }
  G_APPLICATION_CLASS(my_application_parent_class)
      ->dbus_unregister(application, connection, object_path);
}

static void quit_activated(GSimpleAction* action, GVariant* parameter, gpointer user_data) {
  g_application_quit(G_APPLICATION(user_data));
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  GSimpleAction* quit = g_simple_action_new("quit", nullptr);
  g_signal_connect(quit, "activate", G_CALLBACK(quit_activated), application);
  g_action_map_add_action(G_ACTION_MAP(application), G_ACTION(quit));
  g_object_unref(quit);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  cancel_focus_check(self);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_APPLICATION_CLASS(klass)->dbus_register = my_application_dbus_register;
  G_APPLICATION_CLASS(klass)->dbus_unregister = my_application_dbus_unregister;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  // Unique, so a second run reaches the first over D-Bus instead of
  // opening another window.
  return MY_APPLICATION(g_object_new(my_application_get_type(), "application-id", APPLICATION_ID,
                                     "flags", static_cast<GApplicationFlags>(0), nullptr));
}

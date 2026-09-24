#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Method channel used to hand file paths to an already-running Dart engine
// — see my_application_open()'s doc comment for why this exists instead of
// only using fl_dart_project_set_dart_entrypoint_arguments (which only
// affects a brand-new engine at startup, not one that's already running).
static const char* kFileChannelName = "com.musicplayer.music_player/files";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // Set once on first activation/open and reused afterward — see
  // my_application_ensure_window()'s doc comment for why this must be
  // idempotent under GApplication's single-instance model.
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* file_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Creates the window/engine/view on first activation only. GApplication's
// single-instance model (see my_application_new()'s G_APPLICATION_HANDLES_OPEN
// flag, which implies uniqueness unless G_APPLICATION_NON_UNIQUE is set)
// means activate()/open() can each be called multiple times over the life
// of one process — every subsequent launch while this one is already
// running re-delivers to this same primary instance rather than starting a
// new process. Without this idempotency check, a second launch would have
// created a second window/engine inside the same process instead of
// presenting the existing one.
static void my_application_ensure_window(MyApplication* self) {
  if (self->window != nullptr) {
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "MysticJam");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "MysticJam");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->file_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kFileChannelName, FL_METHOD_CODEC(fl_standard_method_codec_new()));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  my_application_ensure_window(self);
  gtk_window_present(self->window);
}

// Implements GApplication::open — called with the file(s) a user opened
// this app with, whether from the command line, a file manager double
// click, or (most importantly for single-instance behavior) forwarded here
// automatically by GLib over D-Bus from a second `music_player <file>`
// invocation while this instance is already the running primary. Handles
// both "app not running yet" (creates the window here, same as activate())
// and "app already running" (just forwards the paths to the live Dart
// engine and raises the window) with the same code path.
static void my_application_open(GApplication* application, GFile** files,
                                 gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  my_application_ensure_window(self);

  g_autoptr(GPtrArray) paths =
      g_ptr_array_new_with_free_func(g_free);
  for (gint i = 0; i < n_files; i++) {
    gchar* path = g_file_get_path(files[i]);
    if (path != nullptr) {
      g_ptr_array_add(paths, path);
    }
  }
  // NULL-terminate for fl_value_new_list_from_strv.
  g_ptr_array_add(paths, nullptr);

  if (self->file_channel != nullptr && paths->len > 1) {
    g_autoptr(FlValue) args = fl_value_new_list_from_strv(
        reinterpret_cast<const gchar* const*>(paths->pdata));
    fl_method_channel_invoke_method(self->file_channel, "openFiles", args,
                                    nullptr, nullptr, nullptr);
  }

  gtk_window_present(self->window);
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // Any non-flag argument is treated as a file to open (launching from a
  // terminal with a file path, or being invoked by a file manager) — routed
  // through g_application_open() rather than g_application_activate() so
  // GApplication's own single-instance machinery does the right thing: if
  // another instance is already the primary, this forwards the files to it
  // over D-Bus and this process exits; otherwise GApplication calls
  // my_application_open() directly, in this same process.
  g_autoptr(GPtrArray) files =
      g_ptr_array_new_with_free_func(g_object_unref);
  for (int i = 0; self->dart_entrypoint_arguments != nullptr &&
                  self->dart_entrypoint_arguments[i] != nullptr;
       i++) {
    const gchar* arg = self->dart_entrypoint_arguments[i];
    if (arg[0] == '-') {
      continue;  // a flag, not a file path
    }
    g_ptr_array_add(files, g_file_new_for_commandline_arg(arg));
  }

  if (files->len > 0) {
    g_application_open(application,
                       reinterpret_cast<GFile**>(files->pdata), files->len,
                       "");
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->file_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // G_APPLICATION_HANDLES_OPEN (replacing the scaffolded default's
  // G_APPLICATION_NON_UNIQUE) is what actually turns on GLib's built-in
  // single-instance behavior: without NON_UNIQUE, GApplication registers
  // this application-id on the session D-Bus, and a second launch detects
  // the existing owner and forwards to it instead of starting a second
  // process. HANDLES_OPEN additionally enables the open() vtable used above
  // for file-path forwarding, both from the command line and from a file
  // manager association.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}

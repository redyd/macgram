#include "my_application.h"

// The Flutter engine applies its initial, empty cursor name when the view is
// created, before the framework has chosen a cursor; GDK then reports
// "Unable to load  from the cursor theme". Drop that one message only.
static GLogWriterOutput log_writer(GLogLevelFlags level,
                                   const GLogField* fields,
                                   gsize n_fields,
                                   gpointer user_data) {
  for (gsize i = 0; i < n_fields; i++) {
    if (g_strcmp0(fields[i].key, "MESSAGE") == 0 &&
        g_strcmp0(static_cast<const gchar*>(fields[i].value),
                  "Unable to load  from the cursor theme") == 0) {
      return G_LOG_WRITER_HANDLED;
    }
  }
  return g_log_writer_default(level, fields, n_fields, user_data);
}

int main(int argc, char** argv) {
  g_log_set_writer_func(log_writer, nullptr, nullptr);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

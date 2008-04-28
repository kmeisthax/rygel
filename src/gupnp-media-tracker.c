/*
 * Copyright (C) 2008 Zeeshan Ali <zeenix@gmail.com>.
 * Copyright (C) 2007 OpenedHand Ltd.
 *
 * Author: Zeeshan Ali <zeenix@gmail.com>
 *         Jorn Baayen <jorn@openedhand.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include <string.h>
#include <libgupnp/gupnp.h>
#include <libgupnp-av/gupnp-av.h>
#include <dbus/dbus-glib.h>

#include "gupnp-media-tracker.h"

#define HOME_DIR_ALIAS "/media"

#define TRACKER_SERVICE "org.freedesktop.Tracker"
#define TRACKER_PATH "/org/freedesktop/tracker"

#define METADATA_IFACE "org.freedesktop.Tracker.Metadata"

G_DEFINE_TYPE (GUPnPMediaTracker,
               gupnp_media_tracker,
               G_TYPE_OBJECT);

struct _GUPnPMediaTrackerPrivate {
        char *root_id;

        GUPnPContext *context;

        DBusGProxy *metadata_proxy;

        GUPnPDIDLLiteWriter *didl_writer;
        GUPnPSearchCriteriaParser *search_parser;
};

enum {
        PROP_0,
        PROP_ROOT_ID,
        PROP_CONTEXT
};

/* Hard-coded item paths, relative to home directory.
 * */
static char *items[] = {
          "entertainment/songs/Maa.mp3",
          "entertainment/songs/Ho.mp3"
};

/* GObject stuff */
static void
gupnp_media_tracker_dispose (GObject *object)
{
        GUPnPMediaTracker *tracker;
        GObjectClass *object_class;

        tracker = GUPNP_MEDIA_TRACKER (object);

        if (tracker->priv->context) {
                g_object_unref (tracker->priv->context);
                tracker->priv->context = NULL;
        }

        /* Free GUPnP resources */
        if (tracker->priv->search_parser) {
                g_object_unref (tracker->priv->search_parser);
                tracker->priv->search_parser = NULL;
        }

        if (tracker->priv->didl_writer) {
                g_object_unref (tracker->priv->didl_writer);
                tracker->priv->didl_writer = NULL;
        }

        if (tracker->priv->root_id) {
                g_free (tracker->priv->root_id);
                tracker->priv->root_id = NULL;
        }

        if (tracker->priv->metadata_proxy) {
                g_object_unref (tracker->priv->metadata_proxy);
                tracker->priv->metadata_proxy = NULL;
        }

        /* Call super */
        object_class = G_OBJECT_CLASS (gupnp_media_tracker_parent_class);
        object_class->dispose (object);
}

static void
gupnp_media_tracker_init (GUPnPMediaTracker *tracker)
{
         tracker->priv = G_TYPE_INSTANCE_GET_PRIVATE (tracker,
                                                     GUPNP_TYPE_MEDIA_TRACKER,
                                                     GUPnPMediaTrackerPrivate);

         /* Create a new DIDL-Lite writer */
        tracker->priv->didl_writer = gupnp_didl_lite_writer_new ();

        /* Create a new search criteria parser */
        tracker->priv->search_parser = gupnp_search_criteria_parser_new ();
}

static GObject *
gupnp_media_tracker_constructor (GType                  type,
                                 guint                  n_construct_params,
                                 GObjectConstructParam *construct_params)
{
        GObject *object;
        GObjectClass *object_class;
        GUPnPMediaTracker *tracker;
        DBusGConnection *connection;
        GError *error;

        object_class = G_OBJECT_CLASS (gupnp_media_tracker_parent_class);
        object = object_class->constructor (type,
                                            n_construct_params,
                                            construct_params);

        if (object == NULL)
                return NULL;

        tracker = GUPNP_MEDIA_TRACKER (object);

        /* Connect to session bus */
        error = NULL;
        connection = dbus_g_bus_get (DBUS_BUS_SESSION, &error);
        if (connection == NULL) {
                g_critical ("Failed to connect to tracker: %s\n",
                            error->message);

                g_error_free (error);

                goto error_case;
        }

        /* Create proxy to metadata interface of tracker object */
        tracker->priv->metadata_proxy =
                dbus_g_proxy_new_for_name (connection,
                                           TRACKER_SERVICE,
                                           TRACKER_PATH,
                                           METADATA_IFACE);
        if (tracker->priv->metadata_proxy == NULL) {
                g_critical ("Failed to create proxy for '%s' object\n",
                            TRACKER_PATH);

                goto error_case;
        }

        /* Host user's home dir */
        gupnp_context_host_path (tracker->priv->context,
                                 g_get_home_dir (),
                                 HOME_DIR_ALIAS);

        return object;

error_case:
        g_object_unref (object);

        return NULL;
}

static void
gupnp_media_tracker_set_property (GObject      *object,
                                  guint         property_id,
                                  const GValue *value,
                                  GParamSpec   *pspec)
{
        GUPnPMediaTracker *tracker;

        tracker = GUPNP_MEDIA_TRACKER (object);

        switch (property_id) {
        case PROP_ROOT_ID:
                tracker->priv->root_id = g_value_dup_string (value);
                break;
        case PROP_CONTEXT:
                tracker->priv->context = g_value_dup_object (value);
                break;
        default:
                G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
                break;
        }
}

static void
gupnp_media_tracker_get_property (GObject    *object,
                                  guint       property_id,
                                  GValue     *value,
                                  GParamSpec *pspec)
{
        GUPnPMediaTracker *tracker;

        tracker = GUPNP_MEDIA_TRACKER (object);

        switch (property_id) {
        case PROP_ROOT_ID:
                g_value_set_string (value, tracker->priv->root_id);
                break;
        case PROP_CONTEXT:
                g_value_set_object (value, tracker->priv->context);
                break;
        default:
                G_OBJECT_WARN_INVALID_PROPERTY_ID (object, property_id, pspec);
                break;
        }
}

static void
gupnp_media_tracker_class_init (GUPnPMediaTrackerClass *klass)
{
        GObjectClass *object_class;

        object_class = G_OBJECT_CLASS (klass);

        object_class->set_property = gupnp_media_tracker_set_property;
        object_class->get_property = gupnp_media_tracker_get_property;
        object_class->dispose = gupnp_media_tracker_dispose;
        object_class->constructor = gupnp_media_tracker_constructor;

        g_type_class_add_private (klass, sizeof (GUPnPMediaTrackerPrivate));

        /**
         * GUPnPMediaTracker:root-id
         *
         * ID of the root container.
         **/
        g_object_class_install_property
                (object_class,
                 PROP_ROOT_ID,
                 g_param_spec_string ("root-id",
                                      "RootID",
                                      "ID of the root container",
                                      NULL,
                                      G_PARAM_READWRITE |
                                      G_PARAM_CONSTRUCT_ONLY |
                                      G_PARAM_STATIC_NAME |
                                      G_PARAM_STATIC_NICK |
                                      G_PARAM_STATIC_BLURB));

        /**
         * GUPnPMediaTracker:context
         *
         * The GUPnP context to use.
         **/
        g_object_class_install_property
                (object_class,
                 PROP_CONTEXT,
                 g_param_spec_object ("context",
                                      "Context",
                                      "The GUPnP context to use",
                                      GUPNP_TYPE_CONTEXT,
                                      G_PARAM_READWRITE |
                                      G_PARAM_CONSTRUCT_ONLY |
                                      G_PARAM_STATIC_NAME |
                                      G_PARAM_STATIC_NICK |
                                      G_PARAM_STATIC_BLURB));
}

static void
add_root_container (const char          *root_id,
                    GUPnPDIDLLiteWriter *didl_writer)
{
        guint child_count;

        /* Count items */
        for (child_count = 0; items[child_count][0]; child_count++);

        gupnp_didl_lite_writer_start_container (didl_writer,
                                                root_id,
                                                "-1",
                                                child_count,
                                                FALSE,
                                                FALSE);

        gupnp_didl_lite_writer_add_string
                        (didl_writer,
                         "class",
                         GUPNP_DIDL_LITE_WRITER_NAMESPACE_UPNP,
                         NULL,
                         "object.container.storageFolder");

        /* End of Container */
        gupnp_didl_lite_writer_end_container (didl_writer);
}

static void
add_item (GUPnPContext        *context,
          GUPnPDIDLLiteWriter *didl_writer,
          const char          *id,
          const char          *parent_id,
          const char          *mime,
          const char          *title,
          const char          *path)
{
        GUPnPDIDLLiteResource res;

        gupnp_didl_lite_writer_start_item (didl_writer,
                                           id,
                                           parent_id,
                                           NULL,
                                           FALSE);

        /* Add fields */
        gupnp_didl_lite_writer_add_string (didl_writer,
                                           "title",
                                           GUPNP_DIDL_LITE_WRITER_NAMESPACE_DC,
                                           NULL,
                                           title);

        gupnp_didl_lite_writer_add_string
                        (didl_writer,
                         "class",
                         GUPNP_DIDL_LITE_WRITER_NAMESPACE_UPNP,
                         NULL,
                         "object.item.audioItem.musicTrack");

        gupnp_didl_lite_writer_add_string
                        (didl_writer,
                         "album",
                         GUPNP_DIDL_LITE_WRITER_NAMESPACE_UPNP,
                         NULL,
                         "Some album");

        /* Add resource data */
        gupnp_didl_lite_resource_reset (&res);

        /* URI */
        res.uri = g_strdup_printf ("http://%s:%d%s/%s",
                                   gupnp_context_get_host_ip (context),
                                   gupnp_context_get_port (context),
                                   HOME_DIR_ALIAS,
                                   path);

        /* Protocol info */
        res.protocol_info = g_strdup_printf ("http-get:*:%s:*", mime);

        gupnp_didl_lite_writer_add_res (didl_writer, &res);

        /* Cleanup */
        g_free (res.protocol_info);
        g_free (res.uri);

        /* End of item */
        gupnp_didl_lite_writer_end_item (didl_writer);
}

static void
add_item_from_db (GUPnPMediaTracker *tracker,
                  const char        *category,
                  const char        *path,
                  const char        *parent_id)
{
        char *keys[] = {"File:Name",
                        "File:Mime",
                        NULL};
        char **values;
        char *full_path;
        gboolean success;
        GError *error;

        full_path = g_build_filename (g_get_home_dir (),
                                      path,
                                      NULL);

        values = NULL;
        error = NULL;
        /* TODO: make this async */
        success = dbus_g_proxy_call (tracker->priv->metadata_proxy,
                                     "Get",
                                     &error,
                                     G_TYPE_STRING, category,
                                     G_TYPE_STRING, full_path,
                                     G_TYPE_STRV, keys,
                                     G_TYPE_INVALID,
                                     G_TYPE_STRV, &values,
                                     G_TYPE_INVALID);
        g_free (full_path);

        if (!success ||
            values == NULL ||
            values[0] == NULL ||
            values[1] == NULL) {
                g_critical ("failed to get metadata for %s.", path);

                if (error) {
                        g_critical ("Reason: %s\n", error->message);

                        g_error_free (error);
                }

                return;
        }

        add_item (tracker->priv->context,
                  tracker->priv->didl_writer,
                  path,
                  parent_id,
                  values[1],
                  values[0],
                  path);
}

GUPnPMediaTracker *
gupnp_media_tracker_new (const char   *root_id,
                         GUPnPContext *context)
{
        GUPnPResourceFactory *factory;

        factory = gupnp_resource_factory_get_default ();

        return g_object_new (GUPNP_TYPE_MEDIA_TRACKER,
                             "root-id", root_id,
                             "context", context,
                             NULL);
}

char *
gupnp_media_tracker_browse (GUPnPMediaTracker *tracker,
                            const char        *container_id,
                            const char        *filter,
                            guint32            starting_index,
                            guint32            requested_count,
                            const char        *sort_criteria,
                            guint32           *number_returned,
                            guint32           *total_matches,
                            guint32           *update_id)
{
        const char *didl;
        char *result;
        guint i;

        if (strcmp (container_id, tracker->priv->root_id) != 0)
                return NULL;

        /* Start DIDL-Lite fragment */
        gupnp_didl_lite_writer_start_didl_lite (tracker->priv->didl_writer,
                                                NULL,
                                                NULL,
                                                TRUE);
        /* Add items */
        for (i = 0; items[i]; i++)
                add_item_from_db (tracker,
                                  "Music",
                                  items[i],
                                  tracker->priv->root_id);

        /* End DIDL-Lite fragment */
        gupnp_didl_lite_writer_end_didl_lite (tracker->priv->didl_writer);

        /* Retrieve generated string */
        didl = gupnp_didl_lite_writer_get_string (tracker->priv->didl_writer);
        result = g_strdup (didl);

        /* Reset the parser state */
        gupnp_didl_lite_writer_reset (tracker->priv->didl_writer);

        *number_returned = i;
        *total_matches = *number_returned;
        *update_id = GUPNP_INVALID_UPDATE_ID;

        return result;
}

char *
gupnp_media_tracker_get_metadata (GUPnPMediaTracker *tracker,
                                  const char        *object_id,
                                  const char        *filter,
                                  const char        *sort_criteria,
                                  guint32           *update_id)
{
        char *result;
        guint i;
        gboolean found;

        /* Start DIDL-Lite fragment */
        gupnp_didl_lite_writer_start_didl_lite (tracker->priv->didl_writer,
                                                NULL,
                                                NULL,
                                                TRUE);
        found = FALSE;
        if (strcmp (object_id, tracker->priv->root_id) == 0) {
                        add_root_container (tracker->priv->root_id,
                                            tracker->priv->didl_writer);

                        found = TRUE;
        } else {
                /* Find and add the item */
                for (i = 0; items[i][0]; i++) {
                        if (strcmp (object_id, items[i]) == 0) {
                                add_item_from_db (tracker,
                                                  "Music",
                                                  items[i],
                                                  tracker->priv->root_id);

                                found = TRUE;

                                break;
                        }
                }
        }

        if (found) {
                const char *didl;

                /* End DIDL-Lite fragment */
                gupnp_didl_lite_writer_end_didl_lite
                                        (tracker->priv->didl_writer);

                /* Retrieve generated string */
                didl = gupnp_didl_lite_writer_get_string
                                        (tracker->priv->didl_writer);
                result = g_strdup (didl);
        } else
                result = NULL;

        /* Reset the parser state */
        gupnp_didl_lite_writer_reset (tracker->priv->didl_writer);

        *update_id = GUPNP_INVALID_UPDATE_ID;

        return result;
}


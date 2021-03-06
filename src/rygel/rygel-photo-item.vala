/*
 * Copyright (C) 2008 Zeeshan Ali <zeenix@gmail.com>.
 * Copyright (C) 2010 Nokia Corporation.
 *
 * Author: Zeeshan Ali (Khattak) <zeeshanak@gnome.org>
 *                               <zeeshan.ali@nokia.com>
 *
 * This file is part of Rygel.
 *
 * Rygel is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Rygel is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

using GUPnP;
using Gee;
using Gst;

/**
 * Represents a photo item.
 */
public class Rygel.PhotoItem : ImageItem {
    public new const string UPNP_CLASS = "object.item.imageItem.photo";

    public string creator;

    public PhotoItem (string         id,
                      MediaContainer parent,
                      string         title,
                      string         upnp_class = PhotoItem.UPNP_CLASS) {
        base (id, parent, title, upnp_class);
    }

    internal override int compare_by_property (MediaObject media_object,
                                               string      property) {
        if (!(media_object is PhotoItem)) {
           return 1;
        }

        var item = media_object as PhotoItem;

        switch (property) {
        case "dc:creator":
            return this.compare_string_props (this.creator, item.creator);
        default:
            return base.compare_by_property (item, property);
        }
    }

    internal override DIDLLiteObject serialize (DIDLLiteWriter writer,
                                                HTTPServer     http_server)
                                                throws Error {
        var didl_item = base.serialize (writer, http_server);

        if (this.creator != null && this.creator != "") {
            var contributor = didl_item.add_creator ();
            contributor.name = this.creator;
        }

        return didl_item;
    }
}

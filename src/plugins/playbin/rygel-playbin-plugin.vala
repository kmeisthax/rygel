/*
 * Copyright (C) 2008 Zeeshan Ali (Khattak) <zeeshanak@gnome.org>.
 * Copyright (C) 2008 Nokia Corporation.
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

using Rygel;
using Gee;

public void module_init (PluginLoader loader) {
    if (loader.plugin_disabled (Playbin.Plugin.NAME)) {
        message ("Plugin '%s' disabled by user, ignoring..",
                 Playbin.Plugin.NAME);

        return;
    }

    var plugin = new Playbin.Plugin ();

    loader.add_plugin (plugin);
}

public class Rygel.Playbin.Plugin : Rygel.MediaRendererPlugin {
    public const string NAME = "Playbin";

    public Plugin () {
        base (Plugin.NAME, _("GStreamer Player"));
    }

    public override MediaPlayer? get_player () {
        return Playbin.Player.get_default ();
    }
}


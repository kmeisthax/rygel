/*
 * Copyright (C) 2009 Nokia Corporation.
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
 * Responsible for management of all transcoders:
 *    - gets the appropriate transcoder given a transcoding target.
 *    - provide all possible transcoding resources for items.
 */
internal abstract class Rygel.TranscodeManager : GLib.Object {
    private ArrayList<Transcoder> transcoders;
    private ArrayList<DLNAProfile> dprofiles;
    private DLNADiscoverer disco;

    private static bool protocol_equal_func (void *a, void *b) {
        var protocol_a = a as ProtocolInfo;
        var protocol_b = b as ProtocolInfo;

        return protocol_a.dlna_profile == protocol_b.dlna_profile &&
               protocol_a.mime_type == protocol_b.mime_type;
    }

    public TranscodeManager () {
        transcoders = new ArrayList<Transcoder> ();
        dprofiles = new ArrayList<DLNAProfile> ();

        var config = MetaConfig.get_default ();

        var transcoding = true;

        try {
            transcoding = config.get_transcoding ();
        } catch (Error err) {}

        if (transcoding) {
            //currently only using non-relaxed, non-extended profiles
            //and 100s timeout
            disco = new DLNADiscoverer(100 * Gst.SECOND, false, false);

            unowned GLib.List<DLNAProfile> profs = disco.list_profiles();
            foreach (DLNAProfile prof in profs) {
                dprofiles.add(prof);
                transcoders.add (new Rygel.DLNATranscoder(prof));
            }
            
            GLib.message("Found %u profiles and created %u transcoders", dprofiles.size, transcoders.size);
        }
    }

    public abstract string create_uri_for_item (MediaItem  item,
                                                int        thumbnail_index,
                                                int        subtitle_index,
                                                string?    transcode_target);

    public void add_resources (DIDLLiteItem didl_item, MediaItem item)
                               throws Error {
        var list = new GLib.List<Transcoder> ();

        foreach (var transcoder in this.transcoders) {
            if (transcoder.get_distance (item) != uint.MAX) {
                list.append (transcoder);
            }
        }

        list.sort_with_data (item.compare_transcoders);
        foreach (var transcoder in list) {
            transcoder.add_resource (didl_item, item, this);
        }
    }

    public Transcoder get_transcoder (string  target) throws Error {
        Transcoder transcoder = null;

        foreach (var iter in this.transcoders) {
            if (iter.can_handle (target)) {
                transcoder = iter;
            }
        }

        if (transcoder == null) {
            throw new HTTPRequestError.NOT_FOUND (
                            _("No transcoder available for target format '%s'"),
                            target);
        }

        return transcoder;
    }

    internal abstract string get_protocol ();

    internal virtual ArrayList<ProtocolInfo> get_protocol_info () {
        var protocol_infos = new ArrayList<ProtocolInfo> (protocol_equal_func);

        foreach (var transcoder in this.transcoders) {
            var protocol_info = new ProtocolInfo ();

            protocol_info.protocol = this.get_protocol ();
            protocol_info.mime_type = transcoder.mime_type;
            protocol_info.dlna_profile = transcoder.dlna_profile;

            protocol_infos.add (protocol_info);
        }

        return protocol_infos;
    }
}


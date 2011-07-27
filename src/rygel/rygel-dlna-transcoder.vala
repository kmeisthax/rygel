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
using Gst;
using Gee;

internal class Rygel.DLNATranscoder : Rygel.Transcoder {
    private DLNAProfile prof;
    private EncodingVideoProfile? videoprof;
    private EncodingAudioProfile? audioprof;
    
    public DLNATranscoder (DLNAProfile profile) {
        var mime_type = profile.get_mime();
        super(mime_type, profile.get_name(), this.upnp_class_from_mime(mime_type));

        this.prof = profile;
        EncodingContainerProfile ecp;
        
        if (profile is EncodingContainerProfile) {
            ecp = profile as EncodingContainerProfile;
            int max_vpass = -1;
            EncodingVideoProfile evp_maxvpass;
        
            foreach (EncodingProfile child in ecp.get_profiles()) {
                if (child is EncodingVideoProfile) {
                    var evp = child as EncodingVideoProfile;
                    if (evp.get_pass() >= max_vpass) {
                        max_vpass = evp.get_pass();
                        evp_maxvpass = evp;
                    }
                } else if (child is EncodingAudioProfile) {
                    this.audioprof = child as EncodingAudioProfile;
                }
            }
        
            this.videoprof = evp_maxvpass;
        } else if (profile is EncodingAudioProfile) {
            this.audioprof = profile as EncodingAudioProfile;
            this.videoprof = null;
        } else if (profile is EncodingVideoProfile) {
            //containerless video stream, probably not even possible, have this case in here anyway
            this.videoprof = profile as EncodingVideoProfile;
        }
    }
    
    /**
     * Gets the Gst.EncodingProfile for this transcoder.
     *
     * @return      the Gst.EncodingProfile for this transcoder.
     */
    protected override EncodingProfile get_encoding_profile () {
        return this.prof.get_encoding_profile();
    };

    private string upnp_class_from_mime(string mime_type) {
        var regex = new Regex("/");
        var msplit = regex.split(mime_type);
        
        switch (msplit[0]) {
            case "audio":
                return AudioItem.UPNP_CLASS;
                break;
            case "video":
                return VideoItem.UPNP_CLASS;
                break;
            case "image":
                return PhotoItem.UPNP_CLASS;
                break;
            default:
                return "";
                break;
        }
    };

    private uint field_difference(int me, unowned Value? theirs) {
        if (theirs == null) {
            return 0;
        } else if (theirs.holds(IntRange)) {
            if (me < theirs.get_int_range_min()) {
                return (me - theirs.get_int_range_min()).abs();
            } else if (me > theirs.get_int_range_max()) {
                return (me - theirs.get_int_range_max()).abs();
            } else {
                return 0;
            }
        } else if (theirs.holds(int)) {
            return (me - theirs.get_int()).abs();
        }
    };

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input video stream bitrate and picture size.
     *
     * @param item          Input VisualItem to transcode, either a video or picture
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input video stream to the selected subprofile
     */
    private uint get_video_distance(VisualItem item) {
        var format = this.videoprof.get_format();
        int num_structs = format.get_size();
        int min_distance = uint.MAX;
        for (int i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            //we need fields: width, height, bitrate
            int diff = 0;
            diff += this.field_difference(item.bitrate, s.get_value("bitrate"));
            diff += this.field_difference(item.width, s.get_value("width"));
            diff += this.field_difference(item.height, s.get_value("height"));
            
            if (diff < min_distance) {
                min_distance = diff;
            }
        }
        
        return min_distance;
    };

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input audio stream's parameters.
     *
     * FIXME: Some audio changes are worse than others.
     * Downmixing 5.1 to 2 should be counted higher than, say, downsampling 48khz to 44.1khz
     *
     * @param item          Input AudioItem stream to compare against.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input audio stream to the selected subprofile
     */
    private uint get_audio_distance(AudioItem item) {
        var format = this.audioprof.get_format();
        int num_structs = format.get_size();
        int min_distance = uint.MAX;
        for (int i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            //we need fields: rate, width, channels, bitrate
            int diff = 0;
            diff += this.field_difference(item.rate, s.get_value("rate"));
            diff += this.field_difference(item.channels, s.get_value("channels"));
            diff += this.field_difference(item.width, s.get_value("width"));
            diff += this.field_difference(item.bitrate, s.get_value("bitrate"));
            
            if (diff < min_distance) {
                min_distance = diff;
            }
        }
        
        return min_distance;
    };

    /**
     * Gets the numeric value that gives an gives an estimate of how hard
     * would it be to trancode @item to target profile of this transcoder.
     *
     * @param item the media item to calculate the distance for
     *
     * @return      the distance from the @item, uint.MIN if providing such a
     *              value is impossible or uint.MAX if it doesn't make any
     *              sense to use this transcoder for @item
     */
    public override uint get_distance (MediaItem item) {
        //we special-case MusicItem as AudioItem
        string our_itemclass = item.UPNP_CLASS
        if (our_itemclass == MusicItem.UPNP_CLASS) {
            our_itemclass = AudioItem.UPNP_CLASS
        }
        
        if (item.UPNP_CLASS != this.upnp_class) {
            return uint.MAX;
        }

        int dist = 0;
        
        if (item is AudioItem && this.audioprof != null) {
            dist += this.get_audio_distance(item as AudioItem);
        }
        
        if (item is VisualItem && this.videoprof != null) {
            dist += this.get_video_distance(item as VisualItem);
        }
        
        return dist;
    };

    public override DIDLLiteResource? add_resource (DIDLLiteItem     didl_item,
                                                   MediaItem        item,
                                                   TranscodeManager manager)
                                                   throws Error {
        var resource = base.add_resource(didl_item, item, manager);
        if (resource == null) return null;
        
        //Video Items need to have width, height, and bitrate.
        //Audio items need channel count, sample frequency, and bitrate.
        //Something with both audio and video gets a bitrate that is the sum of audio + video bitrate,
        //this should be relatively close to the container bitrate (unless we have like 40 sub tracks)
        switch (this.upnp_class) {
            case AudioItem.UPNP_CLASS:
                resource.sampleFrequency = this.audio_rate;
                break;
        }
    };
}

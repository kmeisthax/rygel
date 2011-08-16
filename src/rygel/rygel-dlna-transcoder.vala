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
        base(mime_type, profile.get_name(), this.upnp_class_from_mime(mime_type));

        this.prof = profile;
        EncodingContainerProfile ecp;
        
        if (profile is EncodingContainerProfile) {
            ecp = profile as EncodingContainerProfile;
            int max_vpass = -1;
            EncodingVideoProfile? evp_maxvpass = null;
        
            foreach (EncodingProfile child in ecp.get_profiles()) {
                if (child is EncodingVideoProfile) {
                    var evp = child as EncodingVideoProfile;
                    if (evp.get_pass() >= max_vpass) {
                        max_vpass = (int)evp.get_pass();
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
    }

    private string upnp_class_from_mime(string mime_type) {
        string mimesplit = "";
        
        try {
            var regex = new Regex("/");
            string[] msplit = regex.split(mime_type);
            mimesplit = msplit[0];
        } catch (RegexError rex) {
            return "";
        }
        
        switch (mimesplit) {
            case "audio":
                return AudioItem.UPNP_CLASS;
            case "video":
                return VideoItem.UPNP_CLASS;
            case "image":
                return PhotoItem.UPNP_CLASS;
            default:
                return "";
        }
    }

    private string upnp_class_from_item(MediaItem m) {
        if (MediaItem is MusicItem) {
            return MusicItem.UPNP_CLASS;
        } else if (MediaItem is VideoItem) {
            return VideoItem.UPNP_CLASS;
        } else if (MediaItem is AudioItem) {
            return AudioItem.UPNP_CLASS;
        } else if (MediaItem is ImageItem) {
            return ImageItem.UPNP_CLASS;
        } else {
            return "";
        }
    }

    /**
     * Given an integer and a value, return the difference between that integer and the closest acceptable integer in that value.
     *
     * @param me                The integer we are testing against the field value
     * @param theirs            The field value, nullable
     * @param winning_value     The closest allowed integer within the field value constraints. Out parameter, nullable.
     * @returns     Distance between the input integer and the closest allowed integer.
     */
    private uint field_difference_int(int me, Gst.Value? theirs, out int? winning_value) {
        if (theirs == null) {
            return 0;
        } else if (theirs.holds(typeof(IntRange))) {
            if (me < theirs.get_int_range_min()) {
                if (winning_value != null) {
                    winning_value = theirs.get_int_range_min();
                }
                return (me - theirs.get_int_range_min()).abs();
            } else if (me > theirs.get_int_range_max()) {
                if (winning_value != null) {
                    winning_value = theirs.get_int_range_max();
                }
                return (me - theirs.get_int_range_max()).abs();
            } else {
                if (winning_value != null) {
                    winning_value = me;
                }
                return 0;
            }
        } else if (theirs.holds(typeof(Gst.List))) {
            uint min_distance = uint.MAX;
            
            for (int x = 0; x < theirs.list_get_size(); x++) {
                int winning_altval = 0;
                uint my_dist = this.field_difference_int(me, theirs.list_get_value(x), out winning_altval);
                if (my_dist < min_distance) {
                    min_distance = my_dist;
                    if (winning_value != null) {
                        winning_value = winning_altval;
                    }
                }
            }
            
            return min_distance;
        } else if (theirs.holds(typeof(int))) {
            if (winning_value != null) {
                winning_value = theirs.get_int();
            }
            return (me - theirs.get_int()).abs();
        }

        return 0;
    }

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input video stream bitrate and picture size.
     *
     * @param item          Input VisualItem to transcode, either a video or picture
     * @param didl_item     DIDLLiteResource to fill with information about the VisualItem that's been conformed to this transcoder's profile. Optional.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input video stream to the selected subprofile
     */
    private uint get_video_distance(VisualItem item, DIDLLiteResource? didl_item) {
        var format = this.videoprof.get_format();
        uint num_structs = format.get_size();
        uint min_distance = uint.MAX;
        
        int width = 0;
        int height = 0;
        
        for (uint i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            //we need fields: width, height, bitrate
            int mywidth = 0;
            int myheight = 0;
            
            uint diff = 0;
            //bitrate isn't checked, the AudioItem bitrate covers the whole file
            diff += this.field_difference_int(item.width, s.get_value("width"), out mywidth);
            diff += this.field_difference_int(item.height, s.get_value("height"), out myheight);
            
            if (diff < min_distance) {
                min_distance = diff;
                
                width = mywidth;
                height = myheight;
            }
        }
        
        if (didl_item != null) {
            didl_item.width = width;
            didl_item.height = height;
        }
        
        return min_distance;
    }

    /**
     * Calculate the distance between a particular subprofile we have and an input audio stream's parameters.
     *
     * FIXME: Come up with better weighting for differences
     *
     * @param item          Input AudioItem stream to compare against.
     * @param didl_item     DIDLLiteResource to fill with information about the AudioItem that's been conformed to this transcoder's profile.
     * @param outbitrate    Bitrate of the whole stream. Out parameter, optional.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input audio stream to the selected subprofile
     */
    private uint get_audio_distance(AudioItem item, DIDLLiteResource? didl_item, out int? outbitrate) {
        var format = this.audioprof.get_format();
        uint num_structs = format.get_size();
        uint min_distance = uint.MAX;
        
        //we need fields: rate, width, channels, bitrate
        uint rate = 0;
        uint width = 0;
        uint channels = 0;
        uint bitrate = 0;
        
        for (uint i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            
            uint myrate = 0;
            uint mywidth = 0;
            uint mychannels = 0;
            uint mybitrate = 0;
            
            uint diff = 0;
            diff += this.field_difference_int(item.sample_freq, s.get_value("rate"), out myrate);
            diff += this.field_difference_int(item.channels, s.get_value("channels"), out mywidth);
            diff += this.field_difference_int(item.bits_per_sample, s.get_value("width"), out mychannels);
            diff += this.field_difference_int(item.bitrate, s.get_value("bitrate"), out mybitrate);
            
            if (diff < min_distance) {
                min_distance = diff;
                
                rate = myrate;
                width = mywidth;
                channels = mychannels;
                bitrate = mybitrate;
            }
        }
        
        if (didl_item != null) {
            didl_item.sample_freq = (int)rate;
            didl_item.bits_per_sample = (int)width;
            didl_item.audio_channels = (int)channels;
        }
        
        if (outbitrate != null) {
            /* DIDL specifies bitrate as overall container bitrate, not per-stream bitrate */
            outbitrate = (int)bitrate;
        }
        
        return min_distance;
    }

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
        string itemclass = this.upnp_class_from_item(item);
        string our_itemclass = itemclass;
        
        if (itemclass == MusicItem.UPNP_CLASS) {
            our_itemclass = AudioItem.UPNP_CLASS;
        }
        
        if (itemclass != this.upnp_class) {
            return uint.MAX;
        }

        uint dist = 0;
        
        if (item is AudioItem && this.audioprof != null) {
            dist += this.get_audio_distance(item as AudioItem, null, null);
        }
        
        if (item is VisualItem && this.videoprof != null) {
            dist += this.get_video_distance(item as VisualItem, null);
        }
        
        return dist;
    }

    public override DIDLLiteResource? add_resource (DIDLLiteItem     didl_item,
                                                   MediaItem        item,
                                                   TranscodeManager manager)
                                                   throws Error {
        var resource = base.add_resource(didl_item, item, manager);
        if (resource == null) return null;
        
        //Video Items need to have width, height, and bitrate.
        //Audio items need channel count, sample frequency, and bitrate.
        //Bitrate is system bitrate, and stored in the AudioItem class
        int audio_bitrate = 0;
        
        if (item is AudioItem) {
            this.get_audio_distance(item as AudioItem, resource, out audio_bitrate);
        }
        
        if (item is VisualItem) {
            this.get_video_distance(item as VisualItem, resource);
        }
        
        if (audio_bitrate > 0) {
            resource.bitrate = audio_bitrate;
        }

        return resource;
    }
}

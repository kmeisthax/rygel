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

    /**
     * Given an integer and a value, return the difference between that integer and the closest acceptable integer in that value.
     *
     * @param me                The integer we are testing against the field value
     * @param theirs            The field value, nullable
     * @param winning_value     The closest allowed integer within the field value constraints. Out parameter, nullable.
     * @returns     Distance between the input integer and the closest allowed integer.
     */
    private uint field_difference_int(int me, unowned Gst.Value? theirs, out int? winning_value) {
        if (theirs == null) {
            return 0;
        } else if (theirs.holds(IntRange)) {
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
        } else if (theirs.holds(Gst.List)) {
            uint min_distance = uint.MAX;
            
            for (int x = 0; x < theirs.list_get_size(); x++) {
                int winning_altval = 0;
                uint my_dist = this.field_difference(me, theirs.list_get_value(x), winning_altval);
                if (my_dist < min_distance) {
                    min_distance = my_dist;
                    if (winning_value != null) {
                        winning_value = winning_altval;
                    }
                }
            }
            
            return min_distance;
        } else if (theirs.holds(int)) {
            if (winning_value != null) {
                winning_value = theirs.get_int();
            }
            return (me - theirs.get_int()).abs();
        }
    };

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input video stream bitrate and picture size.
     *
     * @param item          Input VisualItem to transcode, either a video or picture
     * @param didl_item     DIDLLiteResource to fill with information about the VisualItem that's been conformed to this transcoder's profile. Optional.
     * @param outbitrate    Bitrate of the video stream. Out parameter, optional.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input video stream to the selected subprofile
     */
    private uint get_video_distance(VisualItem item, DIDLLiteResource? didl_item, out int? outbitrate) {
        var format = this.videoprof.get_format();
        int num_structs = format.get_size();
        int min_distance = uint.MAX;
        
        int bitrate = 0;
        int width = 0;
        int height = 0;
        
        for (int i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            //we need fields: width, height, bitrate
            int mybitrate = 0;
            int mywidth = 0;
            int myheight = 0;
            
            int diff = 0;
            diff += this.field_difference_int(item.bitrate, s.get_value("bitrate"), mybitrate);
            diff += this.field_difference_int(item.width, s.get_value("width"), mywidth);
            diff += this.field_difference_int(item.height, s.get_value("height"), myheight);
            
            if (diff < min_distance) {
                min_distance = diff;
                
                bitrate = mybitrate;
                width = mywidth;
                height = myheight;
            }
        }
        
        if (didl_item != null) {
            didl_item.width = width;
            didl_item.height = height;
        }
        
        if (outbitrate != null) {
            /* DIDL specifies bitrate as overall container bitrate, not per-stream bitrate */
            outbitrate = bitrate;
        }
        
        return min_distance;
    };

    /**
     * Calculate the distance between a particular subprofile we have and an input audio stream's parameters.
     *
     * FIXME: Come up with better weighting for differences
     *
     * @param item          Input AudioItem stream to compare against.
     * @param didl_item     DIDLLiteResource to fill with information about the AudioItem that's been conformed to this transcoder's profile.
     * @param outbitrate    Bitrate of the video stream. Out parameter, optional.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input audio stream to the selected subprofile
     */
    private uint get_audio_distance(AudioItem item, DIDLLiteResource? didl_item, out int? outbitrate) {
        var format = this.audioprof.get_format();
        int num_structs = format.get_size();
        int min_distance = uint.MAX;
        
        //we need fields: rate, width, channels, bitrate
        int rate = 0;
        int width = 0;
        int channels = 0;
        int bitrate = 0;
        
        for (int i = 0; i < num_structs; i++) {
            var s = format.get_structure(i);
            
            int myrate = 0;
            int mywidth = 0;
            int mychannels = 0;
            int mybitrate = 0;
            
            int diff = 0;
            diff += this.field_difference_int(item.rate, s.get_value("rate"), myrate);
            diff += this.field_difference_int(item.channels, s.get_value("channels"), mywidth);
            diff += this.field_difference_int(item.width, s.get_value("width"), mychannels);
            diff += this.field_difference_int(item.bitrate, s.get_value("bitrate"), mybitrate);
            
            if (diff < min_distance) {
                min_distance = diff;
                
                rate = myrate;
                width = mywidth;
                channels = mychannels;
                bitrate = mybitrate;
            }
        }
        
        if (didl_item != null) {
            didl_item.sample-freq = rate;
            didl_item.bits-per-sample = width;
            didl_item.audio-channels = channels;
        }
        
        if (outbitrate != null) {
            /* DIDL specifies bitrate as overall container bitrate, not per-stream bitrate */
            outbitrate = bitrate;
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
            dist += this.get_audio_distance(item as AudioItem, null, null);
        }
        
        if (item is VisualItem && this.videoprof != null) {
            dist += this.get_video_distance(item as VisualItem, null, null);
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
        int audio_bitrate = 0;
        int video_bitrate = 0;
        
        if (item is AudioItem) {
            this.get_audio_distance(item as AudioItem, resource, audio_bitrate);
        }
        
        if (item is VisualItem) {
            this.get_video_distance(item as VisualItem, resource, video_bitrate);
        }
        
        if (audio_bitrate + video_bitrate > 0) {
            resource.bitrate = audio_bitrate + video_bitrate;
        }
    };
}

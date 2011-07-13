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

internal abstract class Rygel.DLNATranscoder : Rygel.Transcoder {
    private DLNAProfile prof;

    //internal information about the transcoder's profile
    //some of the video items also count for pictures
    //Basically, all of these are arrays; each one represents a
    //different GstStructure on a particular stream of caps.
    private ArrayList<int> video_bitrate;
    private ArrayList<int> video_width;
    private ArrayList<int> video_height;

    private ArrayList<int> audio_rate;
    private ArrayList<int> audio_bitrate;
    private ArrayList<int> audio_channels;
    private ArrayList<int> audio_width;
    
    public DLNATranscoder (DLNAProfile prof) {
        var mime_type = prof.get_mime();
        super(mime_type, prof.get_name(), upnp_class_from_mime(mime_type));

        this.prof = prof;
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

    private void setup_profile_information() {
        var profile = this.get_encoding_profile();
        EncodingContainerProfile ecp;
        ArrayList<EncodingProfile> streamprofs = new ArrayList<EncodingProfile>();
        
        if (profile is EncodingContainerProfile) {
            ecp = profile as EncodingContainerProfile;
            foreach (EncodingProfile child in ecp.get_profiles()) {
                streamprofs.add(child);
            }
        } else {
            streamprofs.add(profile);
        }
        
        int max_vpass = -1;
        EncodingVideoProfile evp_maxvpass;
        
        foreach (EncodingProfile child in streamprofs) {
            if (child is EncodingVideoProfile) {
                var evp = child as EncodingVideoProfile;
                if (evp.get_pass() >= max_vpass) {
                    max_vpass = evp.get_pass();
                    evp_maxvpass = evp;
                }
            } else if (child is EncodingAudioProfile) {
                var profcaps = evp.get_format();
                int structmax = profcaps.get_size();
                for (int i = 0; i < structmax; i++) {
                    var capstruct = profcaps.get_structure(i);
                    int audio_rate = 0;
                    int audio_channels = 0;
                    int audio_bitrate = 0;
                    int audio_width = 0;
                    capstruct.get_int("rate", audio_rate);
                    capstruct.get_int("channels", audio_channels);
                    capstruct.get_int("bitrate", audio_bitrate);
                    capstruct.get_int("width", audio_width);

                    this.audio_rate.add(audio_rate);
                    this.audio_channels.add(audio_channels);
                    this.audio_bitrate.add(audio_bitrate);
                    this.audio_width.add(audio_width);
                }
            }
        }

        //we take video settings from the highest pass in the profile
        //as opposed to the audio, which has no pass# to order on
        var profcaps = evp_maxvpass.get_format();
        int structmax = profcaps.get_size();
        for (int i = 0; i < structmax; i++) {
            var capstruct = profcaps.get_structure(i);
            int video_bitrate = 0;
            int video_width = 0;
            int video_height = 0;
            capstruct.get_int("bitrate", video_bitrate);
            capstruct.get_int("width", video_width);
            capstruct.get_int("height", video_height);

            this.video_bitrate.add(video_bitrate);
            this.video_width.add(video_width);
            this.video_height.add(video_height);
        }
    };

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input video stream bitrate and picture size.
     *
     * @param subprofile    Which 'subprofile' to use.
     * @param item          Input VisualItem to transcode, either a video or picture
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input video stream to the selected subprofile
     */
    private int get_video_distance(int subprofile, VisualItem item) {
        int our_bitrate = this.video_bitrate.get(subprofile);
        int our_width = this.video_width.get(subprofile);
        int our_height = this.video_height.get(subprofile);

        return (item.bitrate - our_bitrate).abs() +
               (width - our_width).abs() + (height - our_height).abs();
    };

    /**
     * Calculate the distance between a particular subprofile we have
     * and an input audio stream's parameters.
     *
     * FIXME: Some audio changes are worse than others.
     * Downmixing 5.1 to 2 should be counted higher than, say, downsampling 48khz to 44.1khz
     *
     * @param subprofile    Which 'subprofile' to use.
     * @param item          Input AudioItem stream to compare against.
     * @return      An integer distance assessment as to the difficulty
     *              of transcoding input audio stream to the selected subprofile
     */
    private int get_audio_distance(int subprofile, AudioItem item) {
        int our_rate = this.audio_rate.get(subprofile);
        int our_width = this.audio_width.get(subprofile);
        int our_channels = this.audio_channels.get(subprofile);
        int our_bitrate = this.audio_bitrate.get(subprofile);

        return (item.bitrate - our_bitrate).abs() +
               (item.bits_per_sample - our_width).abs() +
               (item.channels - our_channels).abs() +
               (item.sample_freq - our_rate).abs();
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

        int min_audiodist = uint.MAX;
        int min_videodist = uint.MAX;
        
        if (item is AudioItem) {
            AudioItem 
            for (int i = 0; i < this.audio_bitrate.size; i++) {
                int our_audiodist = this.get_audio_distance(i, item.
            }
        }
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

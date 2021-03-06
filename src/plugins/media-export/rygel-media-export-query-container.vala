/*
 * Copyright (C) 2009,2010 Jens Georg <mail@jensge.org>.
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

using Gee;
using GUPnP;

internal class Rygel.MediaExport.QueryContainer : DBContainer {
    public static const string PREFIX = "virtual-container:";
    private string attribute;
    private SearchExpression expression;
    private static HashMap<string,string> virtual_container_map = null;
    public string plaintext_id;
    private string pattern = "";

    public QueryContainer (MediaCache media_db,
                           string     id,
                           string     name = "") {
        // parse the id
        // Following the schema:
        // virtual-folder:<class>,? -> get all of that class (eg. Albums)
        // virtual-folder:<class>,<item> -> get all that is contained in that
        //                                  class
        // If an item suffix is present, the children are items, otherwise
        // containers
        // To define a complete hierarchy of containers, use multiple
        // levels:
        // virtual-folder:<meta_data>,?,<meta_data>,? etc.
        // example: virtual-folder:upnp:album,? -> All albums
        //          virtual-folder:upnp:album,The White Album -> All tracks of
        //          the White Album
        //          virtual-folder:dc:creator,The Beatles,upnp:album,? -> All
        //          Albums by the Beatles
        //          the parts not prefixed by virtual-folder: are URL-escaped
        //          virtual-folder:dc:creator,?,upnp:album,? -> start of
        //          hierarchy starting with artists then containing albums of
        //          that artist
        base (media_db, id, name);

        this.plaintext_id = get_virtual_container_definition (id);
        debug ("plaintext ID is: %s", this.plaintext_id);
        var args = this.plaintext_id.split(",");

        if ((args.length % 2) != 0) {
            assert_not_reached ();
        }

        int i = 0;
        while (i < args.length) {
            if (args[i + 1] != "?") {
                update_search_expression (args[i], args[i + 1]);
                if (name == "") {
                    this.title = Uri.unescape_string (args[i + 1]);
                }
            } else {
                args[i + 1] = "%s";
                this.attribute = args[i].replace (PREFIX, "");
                this.attribute = Uri.unescape_string (this.attribute);
                this.pattern = string.joinv(",", args);
                break;
            }
            i += 2;
        }
        this.child_count = this.count_children ();
    }

    private int count_children () {
        try {
            if (this.pattern == "") {
                return (int) this.media_db.get_object_count_by_search_expression
                                        (this.expression,
                                         RootContainer.FILESYSTEM_FOLDER_ID);
            } else {
                var data = this.media_db.get_object_attribute_by_search_expression
                                        (this.attribute,
                                         this.expression,
                                         0,
                                         -1);

                return data.size;
            }
        } catch (Error e) {
            return 0;
        }
    }

    public async override MediaObjects? search (SearchExpression? expression,
                                                uint              offset,
                                                uint              max_count,
                                                out uint          total_matches,
                                                Cancellable?      cancellable)
                                                throws GLib.Error {
        MediaObjects children = null;

        SearchExpression combined_expression;

        if (expression == null) {
            combined_expression = this.expression;
        } else {
            var local_expression = new LogicalExpression ();
            local_expression.operand1 = this.expression;
            local_expression.op = LogicalOperator.AND;
            local_expression.operand2 = expression;
            combined_expression = local_expression;
        }

        try {
            children = this.media_db.get_objects_by_search_expression
                                        (combined_expression,
                                         RootContainer.FILESYSTEM_FOLDER_ID,
                                         offset,
                                         max_count,
                                         out total_matches);
        } catch (MediaCacheError error) {
            if (error is MediaCacheError.UNSUPPORTED_SEARCH) {
                children = new MediaObjects ();
                total_matches = 0;
            } else {
                throw error;
            }
        }

        return children;
    }

    public override async MediaObjects? get_children (uint         offset,
                                                      uint         max_count,
                                                      Cancellable? cancellable)
                                                      throws GLib.Error {
        MediaObjects children;

        if (pattern == "") {
            // this "duplicates" the search expression but using the same
            // search expression in a conjunction shouldn't do any harm
            uint total_matches;
            children = yield this.search (this.expression,
                                          offset,
                                          max_count,
                                          out total_matches,
                                          cancellable);
        } else {
            children = new MediaObjects ();
            var data = this.media_db.get_object_attribute_by_search_expression
                                        (this.attribute,
                                         this.expression,
                                         offset,
                                         max_count);
            foreach (var meta_data in data) {
                var new_id = Uri.escape_string (meta_data, "", true);
                // pattern contains URL escaped text. This means it might
                // contain '%' chars which will makes sprintf crash
                new_id = this.pattern.replace ("%s", new_id);
                register_id (ref new_id);
                var container = new QueryContainer (this.media_db,
                                                    new_id,
                                                    meta_data);
                children.add (container);
            }
        }

        foreach (var child in children) {
            child.parent = this;
        }

        return children;
    }

    public static void register_id (ref string id) {
        var md5 = Checksum.compute_for_string (ChecksumType.MD5, id);
        if (virtual_container_map == null) {
            virtual_container_map = new HashMap<string,string> ();
        }
        if (!virtual_container_map.has_key (md5)) {
            virtual_container_map[md5] = id;
            debug ("Registering %s for %s", md5, id);
        }

        id = PREFIX + md5;
    }

    public static string? get_virtual_container_definition (string hash) {
        var id = hash.replace(PREFIX, "");
        if (virtual_container_map != null &&
            virtual_container_map.has_key (id)) {
            return virtual_container_map[id];
        }

        return null;
    }

    private void update_search_expression (string op1_, string op2) {
        var exp = new RelationalExpression ();
        var op1 = op1_.replace (PREFIX, "");
        exp.operand1 = Uri.unescape_string (op1);
        exp.op = SearchCriteriaOp.EQ;
        exp.operand2 = Uri.unescape_string (op2);
        if (this.expression != null) {
            var exp2 = new LogicalExpression ();
            exp2.operand1 = this.expression;
            exp2.operand2 = exp;
            exp2.op = LogicalOperator.AND;
            this.expression = exp2;
        } else {
            this.expression = exp;
        }
    }
}

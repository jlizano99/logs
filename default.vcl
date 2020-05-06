vcl 4.0;

import geoip;
import directors;

backend default {
        .host = "172.22.4.241";
        .port = "81";
}

backend odds {
        .host = "172.22.4.241";
        .port = "90";
}

sub vcl_recv {		
        set req.backend_hint = default;

        if (req.http.host == "classic.sportsbookreview.com" && 
             (req.url ~ "^/betting-odds.?" || req.url ~ "^/ajax.*" || req.url ~ "^/es/betting-odds.?" || req.url ~ "^/robots\.txt$")) {
                set req.backend_hint = odds;
        }

        call identify_device;

        if (req.http.X-Forwarded-For) {
                        set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
                } else {
                        set req.http.X-Forwarded-For = client.ip;
        }

        #Remove GEO Cookie, because are hashing by GEO IP anyways
        set req.http.Cookie = regsuball(req.http.Cookie, "__GEOIPCC=[^;]+(; )?", "");

        if (req.http.X-Forwarded-For) {
                set req.http.X-GEO = geoip.country_code(regsub(req.http.X-Forwarded-For, ",.*", ""));
        } else {
                set req.http.X-GEO = geoip.ip_country_code(client.ip);
        }

        set req.http.X-HOST = req.http.host;
        # Only deal with "normal" types
        # example if this is a tcp open connection, just pipe (don't inspect or try anything. Its like a proxy)
        if (req.method != "GET" &&
                        req.method != "HEAD" &&
                        req.method != "PUT" &&
                        req.method != "POST" &&
                        req.method != "TRACE" &&
                        req.method != "OPTIONS" &&
                        req.method != "PATCH" &&
                        req.method != "DELETE") {
                /* Non-RFC2616 or CONNECT which is weird. */
                return (pipe);
        }

        # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
        if (req.method != "GET" && req.method != "HEAD") {
                return (pass);  #don't cache
        }

	if (req.url ~ "^/prototype/video/jwplayer/jwplayer.flash.swf$") {
                return (pass); #don't cache
        }

        # Normalize Accept-Encoding header
        # straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
        if (req.http.Accept-Encoding) {
                if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
                        # No point in compressing these
                        unset req.http.Accept-Encoding;
                } elsif (req.http.Accept-Encoding ~ "gzip") {
                        set req.http.Accept-Encoding = "gzip";
                } elsif (req.http.Accept-Encoding ~ "deflate") {
                        set req.http.Accept-Encoding = "deflate";
                } else {
                        # unkown algorithm
                        unset req.http.Accept-Encoding;
                }
        }

        if ( req.url ~ "SportsbooksFilters.ashx" ) {
           set req.url = regsuball(req.url, "(\?|&)(?!books|segmentId)([^=]+=[^&]+)","\1");
           return (hash);
        }

	if (( req.url ~ "RatingGuide_GetInactiveBooks" ) || (req.url ~ "/embed-filters/")) {
           return (hash);
        }

        # Remove all cookies for static files
        # A valid discussion could be held on this line: do you really need to cache static files that don't cause load? Only if you have memory left.
        # Sure, there's disk I/O, but chances are your OS will already have these files in their buffers (thus memory).
        # Before you blindly enable this, have a read here: http://mattiasgeniar.be/2012/11/28/stop-caching-static-files/
        if (req.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|pdf|png|rtf|swf|txt|woff|xml|svg)(\?.*)?$") {
                return (hash);
        }

        #Custom JS Scripts
        if (req.url ~ "^(/js/|/htmlassets/)") {
				#do not unset any cookies sent to iis
                return (hash);
        }

        #Dont Cache The Following for Logged In Users
        if(req.http.Cookie ~ "(bb_userid|sbrSession|bb_password)"){
                return (pass); #don't cache logged in users
        }

        #Don't cache logout request
        if(req.url ~ "\?logout"){
                return (pass);
        }

        # Remove any Google Analytics based cookies
        set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

        #Debug
        set req.http.Cookie = regsuball(req.http.Cookie, "cms-debug=[^;]+(; )?", "");

        #landing pages
        if(req.url ~ "^(/sportsbooks/|/video/|/best-sportsbooks/|/college-football/|/picks/|/nfl-football/|/nfl-prop-bets/)$") {
                return (hash);
        }

        #Video User Pages (take a long time to load)
        if(req.url ~ "^/user/"){
                return (hash);
        }

        #reviews
        if(req.url ~ "^(/5dimes/|/bookmaker/|/bovada/|/pinnacle/)$") {
                return (hash);
        }

        #Home Page
        if(req.url == "/") {
                return (hash);
        }

        #betting odds caching
        if(req.url ~ "^(/betting-odds/|/betting-odds/nfl-football/|/betting-odds/college-football/|/betting-odds/mlb-baseball/)$") {
                return (hash);
        }

        if(req.url ~ "^/betting-odds/\?"){
                return (hash);
        }
}

# The data on which the hashing will take place
sub vcl_hash {
        hash_data(req.url);

        if (req.http.host) {
                hash_data(req.http.host);
        } else {
                hash_data(server.ip);
        }

        # hash cookies for different odds settings
        if(req.url ~ "/betting-odds/"){
                if (req.http.cookie ~ "odds_option_SOUND_ALERTS") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_SOUND_ALERTS=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_SHOW_ROTATION") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_SHOW_ROTATION=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_GAME_STATUS_ORDER") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_GAME_STATUS_ORDER=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_SORT_GAMES") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_SORT_GAMES=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_SHOW_PLAYBYPLAY") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_SHOW_PLAYBYPLAY=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_TIME_ZONE") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_TIME_ZONE=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_OPEN_IN_NEW_TAB") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_OPEN_IN_NEW_TAB=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_SHOW_SCOREBOARD") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_SHOW_SCOREBOARD=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }

                if (req.http.cookie ~ "odds_option_ODDS_FORMAT") {
                        set req.http.X-TMP = regsub(req.http.cookie, ".*odds_option_ODDS_FORMAT=([^;]+);.*", "\1");
                        hash_data(req.http.X-TMP);
                }
        }

        #Theme Caching
        if (req.http.cookie ~ "cms_theme") {
                set req.http.X-TMP = regsub(req.http.cookie, ".*cms_theme=([^;]+);.*", "\1");
                hash_data(req.http.X-TMP);
        }

        if (req.http.cookie ~ "sbr_theme") {
                set req.http.X-TMP = regsub(req.http.cookie, ".*sbr_theme=([^;]+);.*", "\1");
                hash_data(req.http.X-TMP);
        }

        #We don't cant to cache static resources based on geo or device
        if (!(req.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|pdf|png|rtf|swf|txt|woff|xml|svg)(\?.*)?$")) {
                hash_data(req.http.X-Device);
                hash_data(req.http.X-GEO);
        }
}

sub vcl_backend_response  {

        if (beresp.status == 404 || beresp.status == 500) {
                set beresp.ttl = 0s;
        } else {
                set beresp.ttl = 10s;
                set beresp.grace = 2m;

                if (bereq.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|pdf|png|rtf|swf|txt|woff|xml|svg)(\?.*)?$") {
                        set beresp.ttl = 1h;
                        set beresp.grace = 61m;
                }

                if (bereq.url ~ "SportsbooksFilters.ashx") {
                   set beresp.grace = 30m;
                }

		if (( bereq.url ~ "RatingGuide_GetInactiveBooks" ) || (bereq.url ~ "/embed-filters/")) {
                   set beresp.grace = 30m;
                }

                #events sitemap caching for 1 hour
                if (bereq.url ~ "^[^?]*sitemap-events-[^?]+\.(xml)(\?.*)?$") {
                        set beresp.ttl = 1h;
                        set beresp.grace = 30m;
                }
                #sitemap caching for 5 minutes
                elsif (bereq.url ~ "^[^?]*\.(xml)(\?.*)?$") {
                        set beresp.ttl = 5m;
                        set beresp.grace = 30m;
                }
        }

        return(deliver);
}

sub vcl_hit {
        if (obj.ttl >= 0s) {
                return (deliver);
        }
        if (obj.ttl + obj.grace > 0s) {
                return (deliver);
        }
        return (fetch);
}

sub vcl_deliver {
        if (obj.hits > 0) {
                                set resp.http.X-Cacher = "HIT";
                } else {
                                set resp.http.X-Cacher = "MISS";
        }

        set resp.http.X-GEO = req.http.X-GEO;
        set resp.http.X-Device = req.http.X-Device;
        set resp.http.X-Cluster = req.http.X-Cluster;
        unset resp.http.X-Varnish;
        unset resp.http.Via;
        unset resp.http.Age;
        unset resp.http.X-Powered-By;
        unset resp.http.Server;
        unset resp.http.X-AspNet-Version;
}

# Routine to identify and classify a device based on User-Agent
sub identify_device {

  # Default to classification as a PC
  set req.http.X-Device = "pc";

  if (req.http.User-Agent ~ "iPad" ) {
        # The User-Agent indicates it's a iPad - so classify as a tablet
        set req.http.X-Device = "mobile-tablet";
  }

  elsif (req.http.User-Agent ~ "iP(hone|od)" || req.http.User-Agent ~ "Android" ) {
        # The User-Agent indicates it's a iPhone, iPod or Android - so let's classify as a touch/smart phone
        set req.http.X-Device = "mobile-smart";
  }

  elsif (req.http.User-Agent ~ "SymbianOS" || req.http.User-Agent ~ "^BlackBerry" || req.http.User-Agent ~ "^SonyEricsson" || req.http.User-Agent ~ "^Nokia" || req.http.User-Agent ~ "^SAMSUNG" || req.http.User-Agent ~ "^LG")            {
        # The User-Agent indicates that it is some other mobile devices, so let's classify it as such.
        set req.http.X-Device = "mobile-other";
  }
}

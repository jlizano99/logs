server {
  listen   85;
  server_name  adn.sportsbookreview.com;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;
  client_max_body_size 10M;
  set $backend "production.adn.sportsbookreview.com";
  location / {
      proxy_pass https://$backend;
      proxy_set_header    Host            $host;
      proxy_connect_timeout 60;
      proxy_buffering off;
  }
}

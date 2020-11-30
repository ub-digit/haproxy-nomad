job "haproxy" {
  region      = "global"
  datacenters = ["gubdc1"]
  type        = "service"

  group "haproxy" {
    count = 1


    task "haproxy" {

      driver = "docker"

      config {
        image        = "haproxy:2.2"
        network_mode = "host"

        volumes = [
          "local/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg",
        ]
      }

      template {
        data = <<EOF
defaults
   mode http

global
    stats socket ipv4@127.0.0.1:9999 level admin
    stats socket /var/run/hapee-lb.sock mode 666 level admin
    stats timeout 2m

frontend stats
   bind *:1936
   stats uri /
   stats show-legends
   no log

frontend fe_web
   bind *:80
   use_backend be_gup_frontend_lab if { hdr(host) -i gup-lab.ub.gu.se }
   use_backend be_gup_backend_lab if { hdr(host) -i api.gup-lab.ub.gu.se }
   default_backend be_gup_backend_lab

backend be_gup_frontend_lab
    balance roundrobin
    server-template gup-frontend 3 _gup-frontend-lab._tcp.service.consul resolvers consul resolve-opts allow-dup-ip resolve-prefer ipv4 check

backend be_gup_backend_lab
    balance roundrobin
    server-template gup-api 3 _gup-api-lab._tcp.service.consul resolvers consul resolve-opts allow-dup-ip resolve-prefer ipv4 check

resolvers consul
  nameserver consul 127.0.0.1:8600
  accepted_payload_size 8192
  hold valid 5s
EOF

        destination = "local/haproxy.cfg"
      }

      service {
        name = "haproxy"
        port = "http"

        check {
          name     = "alive"
          type     = "tcp"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 200
        memory = 128
        network {
          port "http" {
            static = 80
          }

          port "haproxy_ui" {
            static = 1936
          }
        }

      }
    }
  }
}

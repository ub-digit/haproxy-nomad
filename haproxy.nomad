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
  {{- range $service := services "@gubdc1"}}
    {{- if $service.Tags | contains "haproxy"}}
      {{- range service $service.Name -}}
        {{scratch.Set "hostname" .ServiceMeta.hostname}}
      {{- end}}
  use_backend {{$service.Name | replaceAll "-" "_"}} if { hdr(host) -i {{scratch.Get "hostname"}} }
    {{- end}}
  {{- end}}
  default_backend gup_frontend_lab

{{range $service := services "@gubdc1"}}
  {{- if $service.Tags | contains "haproxy"}}
backend {{ $service.Name | replaceAll "-" "_"}}
  balance roundrobin
  server-template {{$service.Name}} 3 _{{$service.Name}}._tcp.service.consul resolvers consul resolve-opts allow-dup-ip resolve-prefer ipv4 check
  {{- end}}
{{- end}}

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

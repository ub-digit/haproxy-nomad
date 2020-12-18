job "haproxy" {
  region      = "global"
  datacenters = ["gubdc1"]
  type        = "service"

  vault {
    policies = ["nomad-server"]
    change_mode = "restart"
  }

  group "haproxy" {
    count = 1

    task "haproxy" {

      driver = "docker"

      config {
        image        = "haproxy:2.2"
        network_mode = "host"

        volumes = [
          "local/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg",
          "local/dhparam:/usr/local/etc/haproxy/dhparam",
[[range $vault_cert := $.vault_certs]]
          "local/[[$vault_cert]].pem:/opt/[[$vault_cert]].pem",[[end]]
          "local/ca.pem:/usr/local/etc/haproxy/ca.pem"
        ]
      }

      template {
        data = <<EOF
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
-----END DH PARAMETERS-----
EOF
        destination = "local/dhparam"
      }
[[range $vault_cert := $.vault_certs ]]
      template {
        data = "{{with secret \"secret/certs/haproxy\"}}{{.Data.data.[[$vault_cert]]}}{{end}}"
        destination = "local/[[$vault_cert]].pem"
      }
[[end]]
      template {
        data = "{{with secret \"secret/certs/haproxy\"}}{{.Data.data.ca}}{{end}}"
        destination = "local/ca.pem"
      }


      template {
        data = <<EOF
defaults
  mode http
  tiimeout connect 10s
  timeout client 30s
  timeout server 30s

global
  stats socket ipv4@127.0.0.1:9999 level admin
  stats socket /var/run/hapee-lb.sock mode 666 level admin
  stats timeout 2m

  ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
  ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
  ssl-default-bind-options prefer-client-ciphers no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

  ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
  ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
  ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

  ssl-dh-param-file /usr/local/etc/haproxy/dhparam

frontend stats
  bind *:1936
  stats uri /
  stats show-legends
  no log

frontend fe_web
  bind :443 ssl crt /opt/ alpn h2,http/1.1
  bind :80
  redirect scheme https code 301 if !{ ssl_fc }

  # HSTS (63072000 seconds)
  http-response set-header Strict-Transport-Security max-age=63072000

  {{- range $service := services "@gubdc1"}}
    {{- if $service.Tags | contains "haproxy"}}
  use_backend {{$service.Name | replaceAll "-" "_"}} if { hdr(host) -i {{ with service $service.Name }}{{- with index . 0}}{{.ServiceMeta.hostname}}{{- end}}{{- end}} }
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

//go:build with_gvisor && !no_tailscale

package outbound

import (
	"context"
	"net"
	"strings"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

type tailscaleListenerTestTunnel struct{ C.Tunnel }

func (tailscaleListenerTestTunnel) Proxies() map[string]C.Proxy { return nil }

func TestTailscaleDialerProxyBindsUDP(t *testing.T) {
	const proxy = "test-dialer-proxy"
	outbound, err := NewTailscale(TailscaleOption{
		BasicOption: BasicOption{DialerProxy: proxy, TunnelForAPI: tailscaleListenerTestTunnel{}},
		Name:        t.Name(),
		StateDir:    t.Name(),
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = outbound.Close() })
	ctx := context.Background()
	conn, err := outbound.server.SystemPacketListener(ctx, "udp4", ":0")
	if err != nil {
		t.Fatalf("bind local UDP socket: %v", err)
	}
	defer conn.Close()
	if addr, ok := conn.LocalAddr().(*net.UDPAddr); !ok || addr.Port == 0 {
		t.Fatalf("unexpected local socket address: %v", conn.LocalAddr())
	}
	control, err := outbound.server.SystemDialer(ctx, "tcp", "127.0.0.1:1")
	if control != nil {
		_ = control.Close()
	}
	if err == nil || !strings.Contains(err.Error(), proxy) {
		t.Fatalf("control dial did not use the configured proxy: %v", err)
	}
}

from pathlib import Path
import subprocess


CORE = Path(__file__).resolve().parents[1] / 'Clash.Meta'
changed = []


def update(name, *edits):
    path = CORE / name
    source = path.read_text()
    for before, after, count in edits:
        if source.count(before) != count:
            raise SystemExit(f'{name}: expected {count} occurrences of {before!r}')
        source = source.replace(before, after)
    path.write_text(source)
    changed.append(path)


def add(name, source):
    path = CORE / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as handle:
        handle.write(source)
    changed.append(path)


add('component/egress/interface.go', '''package egress

import (
    "net"
    "net/netip"
    "syscall"

    "github.com/metacubex/mihomo/component/iface"
)

func Interface(socket any) string {
    var source net.Addr
    for depth := 0; socket != nil && depth < 24; depth++ {
        if conn, ok := socket.(interface{ LocalAddr() net.Addr }); ok {
            if addr := conn.LocalAddr(); localIP(addr).IsValid() {
                source = addr
            }
        }
        if conn, ok := socket.(syscall.Conn); ok {
            if raw, err := conn.SyscallConn(); err == nil {
                if index := boundInterface(raw); index > 0 {
                    if device, err := net.InterfaceByIndex(index); err == nil {
                        return interfaceLabel(device.Name)
                    }
                }
            }
        }
        switch conn := socket.(type) {
        case interface{ NetConn() net.Conn }:
            socket = conn.NetConn()
        case interface{ Upstream() any }:
            socket = conn.Upstream()
        case interface{ Unwrap() net.Conn }:
            socket = conn.Unwrap()
        default:
            socket = nil
        }
    }
    return interfaceLabel(sourceInterface(localIP(source)))
}

func localIP(addr net.Addr) netip.Addr {
    if wrapped, ok := addr.(interface{ RawAddr() net.Addr }); ok {
        addr = wrapped.RawAddr()
    }
    if addr == nil {
        return netip.Addr{}
    }
    endpoint, err := netip.ParseAddrPort(addr.String())
    if err != nil || endpoint.Addr().IsUnspecified() || endpoint.Addr().IsLoopback() {
        return netip.Addr{}
    }
    return endpoint.Addr().Unmap()
}

func sourceInterface(ip netip.Addr) string {
    if !ip.IsValid() {
        return ""
    }
    devices, err := iface.Interfaces()
    if err != nil {
        return ""
    }
    var result string
    for name, device := range devices {
        if ip.Zone() != "" && ip.Zone() != name {
            continue
        }
        for _, address := range device.Addresses {
            if address.Addr().Unmap() != ip.WithZone("") {
                continue
            }
            if result != "" && result != name {
                return ""
            }
            result = name
        }
    }
    return result
}
''')

add('component/egress/interface_darwin.go', '''package egress

import (
    "context"
    "os/exec"
    "strings"
    "sync"
    "syscall"
    "time"

    "golang.org/x/sys/unix"
)

func boundInterface(raw syscall.RawConn) int {
    var index int
    _ = raw.Control(func(fd uintptr) {
        index, _ = unix.GetsockoptInt(int(fd), unix.IPPROTO_IP, unix.IP_BOUND_IF)
        if index == 0 {
            index, _ = unix.GetsockoptInt(int(fd), unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF)
        }
    })
    return index
}

var ports struct {
    sync.Mutex
    labels map[string]string
    nextRefresh time.Time
}

func interfaceLabel(device string) string {
    if !strings.HasPrefix(device, "en") {
        return device
    }
    ports.Lock()
    defer ports.Unlock()
    if time.Now().After(ports.nextRefresh) {
        ports.nextRefresh = time.Now().Add(15 * time.Second)
        ctx, cancel := context.WithTimeout(context.Background(), 400 * time.Millisecond)
        output, err := exec.CommandContext(ctx, "/usr/sbin/networksetup", "-listallhardwareports").Output()
        cancel()
        if err == nil {
            ports.labels = hardwarePorts(string(output))
        }
    }
    if name := ports.labels[device]; name != "" {
        return name
    }
    return device
}

func hardwarePorts(output string) map[string]string {
    labels := make(map[string]string)
    var port string
    for _, line := range strings.Split(output, "\\n") {
        if value, ok := strings.CutPrefix(line, "Hardware Port: "); ok {
            port = value
        }
        if value, ok := strings.CutPrefix(line, "Device: "); ok {
            switch port {
            case "Wi-Fi", "AirPort":
                labels[value] = "Wi-Fi"
            case "iPhone USB":
                labels[value] = "iPhone USB"
            }
            port = ""
        }
    }
    return labels
}
''')

add('component/egress/interface_other.go', '''//go:build !darwin

package egress

import "syscall"

func boundInterface(syscall.RawConn) int { return 0 }

func interfaceLabel(device string) string { return device }
''')

field = chr(96) + 'json:"egressInterface,omitempty"' + chr(96)
update('tunnel/statistic/tracker.go',
       ('\t"github.com/metacubex/mihomo/common/utils"\n',
        '\t"github.com/metacubex/mihomo/common/utils"\n\t"github.com/metacubex/mihomo/component/egress"\n', 1),
       ('\tRulePayload   string', f'\tEgressInterface string {field}\n\tRulePayload   string', 1),
       ('\t\t\tProviderChain: conn.ProviderChains(),\n',
        '\t\t\tProviderChain: conn.ProviderChains(),\n\t\t\tEgressInterface: egress.Interface(conn),\n', 2))

update('dns/patch.go',
       ('\t"github.com/metacubex/mihomo/common/lru"\n',
        '\t"github.com/metacubex/mihomo/common/lru"\n\t"github.com/metacubex/mihomo/component/egress"\n', 1),
       ('\tUpstream  string\n', '\tUpstream  string\n\tEgressInterface string\n', 1),
       ('\tupstreams map[*D.Msg]string\n', '\tupstreams map[*D.Msg]string\n\tinterfaces map[*D.Msg]string\n', 1),
       ('\t\tupstreams: map[*D.Msg]string{},\n', '\t\tupstreams: map[*D.Msg]string{},\n\t\tinterfaces: map[*D.Msg]string{},\n', 1),
       ('func (t *exchangeTrace) finish(', '''func traceInterface(ctx context.Context, msg *D.Msg, name string) {
    trace, _ := ctx.Value(exchangeTraceKey{}).(*exchangeTrace)
    if trace == nil || msg == nil || name == "" {
        return
    }
    trace.mu.Lock()
    trace.interfaces[msg] = name
    trace.mu.Unlock()
}

func traceConnection(ctx context.Context, msg *D.Msg, conn any) {
    if msg != nil && ctx.Value(exchangeTraceKey{}) != nil {
        traceInterface(ctx, msg, egress.Interface(conn))
    }
}

func (t *exchangeTrace) finish(''', 1),
       ('\t\trecord.Upstream = t.upstreams[msg]\n',
        '\t\trecord.Upstream = t.upstreams[msg]\n\t\trecord.EgressInterface = t.interfaces[msg]\n', 1))

update('dns/doh.go',
       ('\t"sync"\n', '\t"sync"\n\t"sync/atomic"\n', 1),
       ('\t"github.com/metacubex/mihomo/component/ca"\n',
        '\t"github.com/metacubex/mihomo/component/ca"\n\t"github.com/metacubex/mihomo/component/egress"\n', 1),
       ('\t"github.com/metacubex/http"\n',
        '\t"github.com/metacubex/http"\n\t"github.com/metacubex/http/httptrace"\n', 1),
       ('\thttpReq, err := http.NewRequestWithContext(ctx, method, requestUrl.String(), nil)\n', '''    var route atomic.Pointer[string]
    if ctx.Value(exchangeTraceKey{}) != nil {
        ctx = httptrace.WithClientTrace(ctx, &httptrace.ClientTrace{
            GotConn: func(info httptrace.GotConnInfo) {
                name := egress.Interface(info.Conn)
                route.Store(&name)
            },
        })
    }
    httpReq, err := http.NewRequestWithContext(ctx, method, requestUrl.String(), nil)
''', 1),
       ('\treturn resp, err\n}', '''    if name := route.Load(); err == nil && name != nil {
        traceInterface(ctx, resp, *name)
    }
    return resp, err
}''', 1))

update('dns/client.go',
       ('\t\tch <- result{msg, err}\n\t}()\n',
        '\t\tif err == nil {\n\t\t\ttraceConnection(ctx, msg, dConn.Conn)\n\t\t}\n\t\tch <- result{msg, err}\n\t}()\n', 1),
       ('\t\t\tdefer tcpConn.Close()\n\t\t\tdConn.Conn = tcpConn\n\t\t\tmsg, _, err = dClient.ExchangeWithConn(m, dConn)\n',
        '\t\t\tdConn.Conn = tcpConn\n\t\t\tmsg, _, err = dClient.ExchangeWithConn(m, dConn)\n\t\t\tif err == nil {\n\t\t\t\ttraceConnection(ctx, msg, tcpConn)\n\t\t\t}\n\t\t\t_ = tcpConn.Close()\n\t\t\tch <- result{msg, err}\n\t\t\treturn\n', 1))

update('dns/dot.go',
       ('\t\t\tif !t.disableReuse {\n\t\t\t\tt.access.Lock()\n\t\t\t\tif t.connections.Len() >= maxOldDotConns {',
        '\t\t\ttraceConnection(ctx, msg, conn)\n\t\t\tif !t.disableReuse {\n\t\t\t\tt.access.Lock()\n\t\t\t\tif t.connections.Len() >= maxOldDotConns {', 1))

update('dns/doq.go',
       ('\treturn resp, nil\n}\n\n// shouldRetry',
        '\ttraceConnection(ctx, resp, conn)\n\treturn resp, nil\n}\n\n// shouldRetry', 1))

subprocess.run(['gofmt', '-w', *map(str, changed)], check=True)

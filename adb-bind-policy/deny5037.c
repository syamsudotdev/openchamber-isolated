#include <linux/bpf.h>
#include <linux/in.h>

#define SEC(name) __attribute__((section(name), used))

static __inline int permit_bind(struct bpf_sock_addr *ctx)
{
    return ctx->protocol != IPPROTO_TCP ||
           ctx->user_port != __builtin_bswap16(5037);
}

SEC("cgroup/bind4")
int deny_bind4(struct bpf_sock_addr *ctx)
{
    return permit_bind(ctx);
}

SEC("cgroup/bind6")
int deny_bind6(struct bpf_sock_addr *ctx)
{
    return permit_bind(ctx);
}

char _license[] SEC("license") = "GPL";

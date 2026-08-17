# LinkView topology web

AntV G6 frontend for the OpenWrt snapshot API.

```sh
pnpm install
pnpm build
```

Deploy the contents of `dist/` to `/www/topology/` on ImmortalWrt, then open:

```text
http://192.168.16.254/topology/
```

The client fixes one `snapshot_id`, loads node and edge pages in parallel, verifies
the version on every page, and uses compact-box layout. Above 2,500 nodes it groups
large terminal fan-outs by default; users can opt into the full graph.

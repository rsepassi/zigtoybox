# Toybox

Built with Zig

https://github.com/landley/toybox

Toybox version 0.8.10

* Build default config: `zig build`. Equivalent to Toybox's `make defconfig`.
* Specify commands: `zig build -Dallno -DLS`

Defaults to `-Dtarget=<native>-linux-musl` with `.ReleaseSmall`.

### Maximal build

Maximal build that actually builds currently.

```
zig build -Dallyes \
        -DGITFETCH=false \
        -DGITREMOTE=false \
        -DGITINIT=false \
        -DGITCLONE=false \
        -DGITCHECKOUT=false \
        -DTOYBOX_SELINUX=false \
        -DCHCON=false \
        -DGETENFORCE=false \
        -DSETENFORCE=false \
        -DRUNCON=false \
        -DRESTORECON=false \
        -DLOAD_POLICY=false \
        -DTOYBOX_ON_ANDROID=false \
        -DSENDEVENT=false \
        -DLOG=false \
        -DTOYBOX_SMACK=false \
        -DTOYBOX_LIBCRYPTO=false \
        -DTOYBOX_LIBZ=false \
        -DWGET_LIBTLS=false \
        -DUSERADD=false \
        -DUSERDEL=false \
        -DGROUPADD=false \
        -DGROUPDEL=false \
        -DCHSH=false \
        -DSYSLOGD=false
```

Contributions welcome to get these working.

* git: (`GIT*`) needs zlib and openssl
* selinux: (`TOYBOX_SELINUX..TOYBOX_ON_ANDROID`) needs selinux
* android: (`TOYBOX_ON_ANDROID..TOYBOX_SMACK`) needs android
* smack, libcrypto, libz: external libs
* `WGET_LIBTLS`: needs openssl
* `USERADD..SYSLOGD`: error `error: too few arguments to function call, expected
  4, have 3 toybox/lib/pending.h:6:5: note: 'update_password' declared here`
* syslogd: `undefined symbol: facilitynames`, `undefined symbol: prioritynames`

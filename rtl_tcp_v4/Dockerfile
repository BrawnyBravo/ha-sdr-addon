ARG BUILD_FROM
FROM ${BUILD_FROM}

# Why this add-on exists: the librtlsdr shipped by distributions does not
# recognise RTL-SDR Blog V4 hardware. It detects the tuner as a plain R820T and
# every tune attempt fails with "[R82XX] PLL not locked!", so the dongle
# enumerates fine and then decodes nothing. Building the vendor's own fork is
# the only fix; there is no runtime flag for it.
ARG RTLSDR_REF=master

RUN apk add --no-cache libusb jq tini \
    && apk add --no-cache --virtual .build-deps \
        git cmake make g++ libusb-dev pkgconfig \
    && git clone --depth 1 --branch "${RTLSDR_REF}" \
        https://github.com/rtlsdrblog/rtl-sdr-blog /tmp/rtl-sdr-blog \
    && cmake -S /tmp/rtl-sdr-blog -B /tmp/rtl-sdr-blog/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DINSTALL_UDEV_RULES=OFF \
        -DDETACH_KERNEL_DRIVER=ON \
    && make -C /tmp/rtl-sdr-blog/build -j"$(nproc)" \
    && make -C /tmp/rtl-sdr-blog/build install \
    && rm -rf /tmp/rtl-sdr-blog \
    && apk del .build-deps

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/run.sh"]

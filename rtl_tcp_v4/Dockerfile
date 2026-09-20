ARG BUILD_FROM
FROM ${BUILD_FROM}

# Why this add-on exists: the librtlsdr shipped by distributions does not
# recognise RTL-SDR Blog V4 hardware. It detects the tuner as a plain R820T and
# every tune attempt fails with "[R82XX] PLL not locked!", so the dongle
# enumerates fine and then decodes nothing, with no error of its own. Building
# the vendor's fork is the only fix; there is no runtime flag for it.
#
# Everything here is built against that one driver, so every mode benefits.

ARG RTLSDR_REF=master
ARG RTL433_REF=master

RUN apk add --no-cache \
        libusb openssl jq curl tini python3 py3-paho-mqtt \
    && apk add --no-cache --virtual .build-deps \
        git cmake make g++ libusb-dev openssl-dev pkgconfig \
    \
    # --- RTL-SDR Blog driver: librtlsdr, rtl_tcp, rtl_adsb, rtl_power, rtl_test
    && git clone --depth 1 --branch "${RTLSDR_REF}" \
        https://github.com/rtlsdrblog/rtl-sdr-blog /tmp/rtl-sdr-blog \
    && cmake -S /tmp/rtl-sdr-blog -B /tmp/rtl-sdr-blog/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DINSTALL_UDEV_RULES=OFF \
        -DDETACH_KERNEL_DRIVER=ON \
    && make -C /tmp/rtl-sdr-blog/build -j"$(nproc)" \
    && make -C /tmp/rtl-sdr-blog/build install \
    \
    # --- rtl_433: sensors, utility meters, tyre pressure sensors, and more
    && git clone --depth 1 --branch "${RTL433_REF}" \
        https://github.com/merbanan/rtl_433 /tmp/rtl_433 \
    && cmake -S /tmp/rtl_433 -B /tmp/rtl_433/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DENABLE_RTLSDR=ON \
        -DENABLE_SOAPYSDR=OFF \
    && make -C /tmp/rtl_433/build -j"$(nproc)" \
    && make -C /tmp/rtl_433/build install \
    \
    # The Home Assistant MQTT discovery bridge ships in the rtl_433 source tree.
    && install -m 0755 /tmp/rtl_433/examples/rtl_433_mqtt_hass.py \
        /usr/local/bin/rtl_433_mqtt_hass.py \
    \
    && rm -rf /tmp/rtl-sdr-blog /tmp/rtl_433 \
    && apk del .build-deps \
    && ldconfig /usr/local/lib 2>/dev/null || true

ENV LD_LIBRARY_PATH=/usr/local/lib

COPY run.sh /run.sh
COPY diag.py /usr/local/bin/diag.py
RUN chmod a+x /run.sh /usr/local/bin/diag.py

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/run.sh"]

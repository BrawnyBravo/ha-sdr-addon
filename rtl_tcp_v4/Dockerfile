ARG BUILD_FROM
FROM ${BUILD_FROM}

# Why this add-on exists: the librtlsdr shipped by distributions does not
# recognise RTL-SDR Blog V4 hardware. It detects the tuner as a plain R820T and
# every tune attempt fails with "[R82XX] PLL not locked!", so the dongle
# enumerates fine and then decodes nothing, with no error of its own. Building
# the vendor's fork is the only fix; there is no runtime flag for it.
#
# Everything here is built against that one driver, so every mode benefits.

# The mapping patch below is applied to upstream's bridge at build time.
COPY patch_mqtt_hass.py /usr/local/bin/patch_mqtt_hass.py

# Upstream sources are pinned to exact commits so a rebuild always produces the
# same driver and decoder. Bump these on purpose (and the add-on version with them).
# rtl-sdr-blog V1.4.0 (2026-08-10).
ARG RTLSDR_REF=aed0ea19f3a273370a13c9009b96313c75d54c7b
# rtl_433 master as of 2026-10-27.
ARG RTL433_REF=f35183aaf1d2d905d422fd70bcae4eb7349d6186

RUN apk add --no-cache \
        libusb openssl jq curl tini python3 py3-paho-mqtt \
    && apk add --no-cache --virtual .build-deps \
        git cmake make g++ libusb-dev openssl-dev pkgconfig \
    \
    # --- RTL-SDR Blog driver: librtlsdr, rtl_tcp, rtl_adsb, rtl_power, rtl_test
    && git init -q /tmp/rtl-sdr-blog \
    && git -C /tmp/rtl-sdr-blog fetch -q --depth 1 \
        https://github.com/rtlsdrblog/rtl-sdr-blog "${RTLSDR_REF}" \
    && git -C /tmp/rtl-sdr-blog checkout -q FETCH_HEAD \
    && cmake -S /tmp/rtl-sdr-blog -B /tmp/rtl-sdr-blog/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DINSTALL_UDEV_RULES=OFF \
        -DDETACH_KERNEL_DRIVER=ON \
    && make -C /tmp/rtl-sdr-blog/build -j"$(nproc)" \
    && make -C /tmp/rtl-sdr-blog/build install \
    \
    # --- rtl_433: sensors, utility meters, tyre pressure sensors, and more
    && git init -q /tmp/rtl_433 \
    && git -C /tmp/rtl_433 fetch -q --depth 1 \
        https://github.com/merbanan/rtl_433 "${RTL433_REF}" \
    && git -C /tmp/rtl_433 checkout -q FETCH_HEAD \
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
    # That bridge drops the one field a utility meter exists to report: it
    # matches keys case-sensitively and has no mapping for SCM+'s
    # "Consumption" or IDM's "LastConsumption*", so meters get rssi/snr/noise
    # and no reading. The patch is additive and fails the build if the
    # result does not parse. See patch_mqtt_hass.py.
    && python3 /usr/local/bin/patch_mqtt_hass.py \
        /usr/local/bin/rtl_433_mqtt_hass.py \
    \
    && rm -rf /tmp/rtl-sdr-blog /tmp/rtl_433 \
    && apk del .build-deps \
    && { ldconfig /usr/local/lib 2>/dev/null || true; }

ENV LD_LIBRARY_PATH=/usr/local/lib

COPY run.sh /run.sh
COPY diag.py /usr/local/bin/diag.py
RUN chmod a+x /run.sh /usr/local/bin/diag.py

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/run.sh"]

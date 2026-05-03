/*
 * bt-rssi — reads RSSI for a connected BR/EDR Bluetooth device.
 *
 * This binary needs CAP_NET_RAW to open a raw HCI socket.
 * Set it once after compilation:
 *   setcap cap_net_raw+ep /usr/local/bin/bt-rssi
 *
 * Usage:  bt-rssi AA:BB:CC:DD:EE:FF
 * Output: prints dBm integer (e.g. "-65") on success, exits non-zero on failure.
 *
 * https://github.com/SolVerNA/bt-lock-guard
 * License: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "Usage: bt-rssi AA:BB:CC:DD:EE:FF\n");
        return 1;
    }

    int dev_id = hci_get_route(NULL);
    if (dev_id < 0) { perror("hci_get_route"); return 1; }

    int dd = hci_open_dev(dev_id);
    if (dd < 0) { perror("hci_open_dev"); return 1; }

    bdaddr_t bdaddr;
    str2ba(argv[1], &bdaddr);

    /* Resolve MAC → HCI connection handle */
    struct hci_conn_info_req *cr =
        malloc(sizeof(struct hci_conn_info_req) + sizeof(struct hci_conn_info));
    if (!cr) { close(dd); return 1; }

    bacpy(&cr->bdaddr, &bdaddr);
    cr->type = ACL_LINK;

    if (ioctl(dd, HCIGETCONNINFO, cr) < 0) {
        free(cr);
        close(dd);
        return 1;   /* device not connected */
    }

    uint16_t handle = htobs(cr->conn_info->handle);
    free(cr);

    int8_t rssi = 0;
    if (hci_read_rssi(dd, handle, &rssi, 1000) < 0) {
        close(dd);
        return 1;
    }

    printf("%d\n", (int)rssi);
    close(dd);
    return 0;
}

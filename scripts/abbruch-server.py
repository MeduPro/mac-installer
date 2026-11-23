#!/usr/bin/env python3
"""Prüfserver für den Downloader: liefert eine Datei mit Range-Unterstützung und
kappt die Verbindung bei den ersten Anfragen mitten im Download.

    python3 scripts/abbruch-server.py <port> <datei> [abbrueche]

Die ersten `abbrueche` Anfragen (Vorgabe 2) brechen nach etwa einem Drittel des
angefragten Bereichs ab, wie bei einer WLAN-Lücke.
"""

import http.server
import os
import re
import sys

PORT, DATEI = int(sys.argv[1]), sys.argv[2]
ABBRUECHE = int(sys.argv[3]) if len(sys.argv) > 3 else 2
zaehler = {"anfragen": 0}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        zaehler["anfragen"] += 1
        groesse = os.path.getsize(DATEI)
        start = 0
        treffer = re.match(r"bytes=(\d+)-", self.headers.get("Range", ""))
        if treffer:
            start = int(treffer.group(1))
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{groesse - 1}/{groesse}")
        else:
            self.send_response(200)
        laenge = groesse - start
        self.send_header("Content-Length", str(laenge))
        self.send_header("Content-Type", "application/octet-stream")
        self.end_headers()
        abbrechen = zaehler["anfragen"] <= ABBRUECHE
        grenze = laenge // 3 if abbrechen else laenge
        with open(DATEI, "rb") as f:
            f.seek(start)
            gesendet = 0
            while gesendet < grenze:
                block = f.read(min(64 * 1024, grenze - gesendet))
                if not block:
                    break
                self.wfile.write(block)
                gesendet += len(block)
        if abbrechen:
            self.wfile.flush()
            self.connection.shutdown(2)
            self.close_connection = True

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

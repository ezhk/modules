#!/usr/bin/python3

import typing
import urllib3


def get_url_body(url: str, status_code: int = 200, headers: typing.Dict[str, typing.Any] = {}) -> str:
    """Returns URL response data"""
    http = urllib3.PoolManager()

    r = http.request("GET", url, headers=headers)
    if r.status != status_code:
        raise ValueError(f"wrong status code: {r.status}")

    return r.data.decode("utf-8")

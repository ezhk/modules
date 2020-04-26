#!/usr/bin/python3


import urllib3


def get_url_body(url=None, status_code=200, headers={}):
    if url is None:
        return (False, "URL must be defined")

    try:
        http = urllib3.PoolManager()
        r = http.request("GET", url, headers=headers)
        if r.status != status_code:
            return (False, "wrong status code: %s" % r.status)
        return (True, r.data.decode("utf-8"))

    except BaseException as err:
        return (False, str(err))

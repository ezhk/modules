#!/usr/bin/python3


import urllib3
import json


class PDD_DNS:
    """
    Class provide API with PDD's Yandex.
    Include some methods, that allow add/delete/show
    NS records and modify them.
    """

    PDD_DNS_URL = "https://pddimp.yandex.ru/api2/admin/dns"

    def __init__(self, domainname, token):
        self.token = token
        self.domainname = domainname
        self.http = urllib3.PoolManager()

    def _actions_domain(self, action=None, params={}):
        """
        Unified internal method, that allow add/del and modify methods.

        :param actions: string of method name
        :param params: dicts with args for POST body

        return tuple
            :param status: boolean
            :param message: description
        """

        if not action or not params:
            return (False, "_actions_domain: empty input vars")

        url = "%s/%s" % (self.PDD_DNS_URL, action)
        params.update({"domain": self.domainname})

        # POST data format like a string: key1=val1&key2=val2
        post_body = "&".join(
            ["%s=%s" % (key, value) for key, value in params.items()]
        )

        try:
            r = self.http.request(
                "POST",
                url,
                body=post_body,
                headers={
                    "PddToken": self.token,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            if r.status != 200:
                return (False, "wrong status code: %s" % r.status)

            json_obj = json.loads(r.data.decode("utf-8"))
            if "error" in json_obj:
                return (False, "error: %s" % json_obj["error"])
            return (True, json_obj)

        except BaseException as err:
            return (False, str(err))

    def add_domain(self, params={}):
        if "type" not in params:
            return (False, 'add_domain: "type" must be defined')

        return self._actions_domain("add", params)

    def del_domain(self, params={}):
        if "record_id" not in params:
            return (False, 'del_domain: "record_id" must be defined')

        return self._actions_domain("del", params)

    def edit_domain(self, params={}):
        if "record_id" not in params:
            return (False, 'edit_domain: "record_id" must be defined')

        return self._actions_domain("edit", params)

    def list_domain(self):
        url = "%s/list?domain=%s" % (self.PDD_DNS_URL, self.domainname)

        try:
            r = self.http.request("GET", url, headers={"PddToken": self.token})
            if r.status != 200:
                return (False, "wrong status code: %s" % r.status)

            json_obj = json.loads(r.data.decode("utf-8"))
            if "error" in json_obj:
                return (False, json_obj["error"])
            return (True, json_obj)

        except BaseException as err:
            return (False, str(err))

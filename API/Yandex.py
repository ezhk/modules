#!/usr/bin/python3

import json
import typing

import urllib3


class API360:
    """
    Class provides DNS API with 360 API's Yandex.
    Includes methods, that allow add/delete/show
    NS records and modify them.
    """

    DNS_LIST = "https://api360.yandex.net/directory/v1/org/%(org_id)s/domains/%(domain)s/dns?perPage=9999"
    DNS_ADD = "https://api360.yandex.net/directory/v1/org/%(org_id)s/domains/%(domain)s/dns"
    DNS_EDIT = "https://api360.yandex.net/directory/v1/org/%(org_id)s/domains/%(domain)s/dns/%(record_id)s"
    DNS_DELETE = "https://api360.yandex.net/directory/v1/org/%(org_id)s/domains/%(domain)s/dns/%(record_id)s"

    def __init__(self, organization_id: int, domainname: str, token: str):
        self.token = token

        self.org_id = organization_id
        self.domainname = domainname

        self.http = urllib3.PoolManager()

    def list_domain(self) -> typing.Dict[str, typing.Any]:
        """Get domain records list."""

        _url = self.DNS_LIST % {
            "org_id": self.org_id,
            "domain": self.domainname,
        }

        r = self.http.request("GET", _url, headers={"Authorization": f"OAuth {self.token}"})
        if r.status != 200:
            raise ValueError(f"wrong status code response: {r.data}")

        return json.loads(r.data.decode("utf-8"))

    def del_domain(self, record_id: int) -> typing.Dict[str, typing.Any]:
        """Remove record by ID and raise exception on error."""
        _url = self.DNS_DELETE % {"org_id": self.org_id, "domain": self.domainname, "record_id": record_id}

        r = self.http.request("DELETE", _url, headers={"Authorization": f"OAuth {self.token}"})
        if r.status != 200:
            raise ValueError(f"wrong status code response: {r.data}")

        return json.loads(r.data.decode("utf-8"))

    def add_domain(self, address: str, name: str, record_type: str, ttl: int) -> typing.Dict[str, typing.Any]:
        """Method create A/AAAA record type."""

        _url = self.DNS_ADD % {"org_id": self.org_id, "domain": self.domainname}
        _body = json.dumps({"address": address, "name": name, "type": record_type, "ttl": ttl})

        r = self.http.request("POST", _url, body=_body, headers={"Authorization": f"OAuth {self.token}"})
        if r.status != 200:
            raise ValueError(f"wrong status code response: {r.data}")

        return json.loads(r.data.decode("utf-8"))

    def edit_domain(
        self, record_id: int, address: str, name: str, record_type: str, ttl: int
    ) -> typing.Dict[str, typing.Any]:
        """Method modify A/AAAA record type."""

        _url = self.DNS_EDIT % {"org_id": self.org_id, "domain": self.domainname, "record_id": record_id}
        _body = json.dumps({"address": address, "name": name, "type": record_type, "ttl": ttl})

        r = self.http.request("POST", _url, body=_body, headers={"Authorization": f"OAuth {self.token}"})
        if r.status != 200:
            raise ValueError(f"wrong status code response: {r.data}")

        return json.loads(r.data.decode("utf-8"))

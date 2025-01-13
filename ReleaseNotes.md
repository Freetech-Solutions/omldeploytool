# Release Notes - OMniLeads 2.3.0
[2025-01-02]

## Added

* oml-2843 [OMLAPP] - Close Whatsapp conversations command.
* oml-680 [OMLAPP][OMLACD] - Add Direct Inbound Dial to agents endpoint.

## Improvements

* oml-2679 [DEPLOY][DOCKER] - Docker deploy refactor (devenv, testenv & prodenv).
* oml-659 [OMLKAM] - Upgrade to kamailio 5.8 & improve container img size.
* oml-658 [OMLRTP] - Upgrade to Rtpengine mr13.0.1.5 & improve container img size.

## Fixes

* oml-697 [OMLACD] - Time groups & Time conditions fix.
* oml-697 [OMLACD] - Telephony channel audio prompts container volume.
* oml-2854 [OMLAPP] - Optimizations to allow loading big Blacklists.
* oml-2831 [OMLAPP] - Identify Whatsapp contact now shows phone field correctly.
* oml-2856 [OMLAPP] - IVR name change is reflected in IVR as Destination Option.

## Component changes

### OMLAPP (Django/VueJS)

- [Container Img]()
- [Gitlab Repo]()

### OMLACD (Automatic Call Distribution component)

- [Container Img]()
- [Gitlab Repo]()

### OMLSIPProxy (SIP Proxy component)

- [Container Img](https://hub.docker.com/layers/omnileads/kamailio/241109.01/images/sha256-53cfbfeddbb4bce8a3984d32869106339210950aac77f21beff90f06fbbe3153)
- [Gitlab Repo](https://gitlab.com/omnileads/omlkamailio/-/tree/250102.01?ref_type=tags)

### OMLMediaProxy (Media Proxy component)

- [Container Img](https://hub.docker.com/layers/omnileads/rtpengine/241128.01/images/sha256-901f57255a7309719a79a6b13bab468da5b55b17de6473b5e7923f882bd7ee07)
- [Gitlab Repo](https://gitlab.com/omnileads/omlrtpengine/-/blob/250102.01/ReleasesNotes.md?ref_type=tags)

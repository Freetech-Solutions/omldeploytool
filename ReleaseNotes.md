# Release Notes - OMniLeads 2.3.0
[2025-01-20]

## Added

* oml-2843 Close Whatsapp conversations command.
* oml-2724 Better notifications in case of External site interaction errors.
* oml-2765 Show transfer conference members.
* oml-2732 Consultative transfers to campaigns enabled.

## Improvements

* oml-2679 Docker deploy refactor (devenv, testenv & prodenv).
* oml-659 Upgrade to kamailio 5.8 & improve container img size.
* oml-658 Upgrade to Rtpengine mr13.0.1.5 & improve container img size.
* oml-2825 Whatsapp Interactive Menu form validations
* PJSIP parameters optimized for different networking scenarios.

## Fixes

* oml-697 Time groups & Time conditions fix.
* oml-697 Telephony channel audio prompts container volume.
* oml-2854 Optimizations to allow loading big Blacklists.
* oml-2831 Identify Whatsapp contact now shows phone field correctly.
* oml-2856 IVR name change is reflected in IVR as Destination Option.
* oml-2862 Hide Whatsapp Providers "Password Partner" field.
* oml-2861 Fix Whatsapp line wizzard initial field data bug.

## Component changes

### OMLAPP (Django/VueJS)

- [Container Img](https://hub.docker.com/layers/omnileads/omlapp/250122.01/images/sha256-f998e5edaa18452fed11aa1bde456e42e0c6e4f500589ab7efed8145f00e5de4)
- [Gitlab Repo](https://gitlab.com/omnileads/ominicontacto/-/tree/250122.01?ref_type=tags)

### OMLACD (Automatic Call Distribution component)

- [Container Img](https://hub.docker.com/layers/omnileads/asterisk/250117.01/images/sha256-0d20de84b4c4bfefcf8cf7fe7716795bff356a839f420ec594f9fbfba648103d)
- [Gitlab Repo](https://gitlab.com/omnileads/omlacd/-/tree/250122.01?ref_type=tags)

### OMLSIPProxy (SIP Proxy component)

- [Container Img](https://hub.docker.com/layers/omnileads/kamailio/241109.01/images/sha256-53cfbfeddbb4bce8a3984d32869106339210950aac77f21beff90f06fbbe3153)
- [Gitlab Repo](https://gitlab.com/omnileads/omlkamailio/-/tree/250102.01?ref_type=tags)

### OMLMediaProxy (Media Proxy component)

- [Container Img](https://hub.docker.com/layers/omnileads/rtpengine/241128.01/images/sha256-901f57255a7309719a79a6b13bab468da5b55b17de6473b5e7923f882bd7ee07)
- [Gitlab Repo](https://gitlab.com/omnileads/omlrtpengine/-/blob/250102.01/ReleasesNotes.md?ref_type=tags)

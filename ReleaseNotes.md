# Release Notes - OMniLeads 2.4.0
[2025-04-10]

## Added

* oml-2746 New Disposition form List field with options fetched from CRM.
* oml-2788 Possibility to add Sub-Dispositions.
* oml-2889 Supervisiors can send messages to Agents.
* oml-2924 Massive Users profiles imports.
* oml-2938 New endpoint for multinum calls.

## Changed

* oml-2750 Whatsapp Line Wizard allows selection of any inbound campaign.
* oml-2892 Enable recordings set by default in Campaign Wizard.
* oml-2891 DB Select input with search capabilities in Campaign Wizard.
* oml-2844 Whatsapp Line Interactive Menu management allows non connected menues.
* oml-2845 Is now not possible to deactivate Whatsapp for Line destination campaigns.
* oml-2934 Inbound Routes language options are now selected from installed asterisk audios.
* oml-2738 Decoupling recording report generation for async processing.
* oml-2887 Change in the way Database Contacts are counted.
* oml-2888 Possibility to select the Agenda telephone.
* oml-2922 Campaign lists views can be ordered by id.

## Fixed

* oml-2859 Fix command for closing conversations.
* oml-2722 Fix External Site Authentication form validation
* Error testing External Site Authentication.
* Error in notification of External Site interaction result.
* Race condition with LlamadaLog log and External Site interaction with 'datetime' parameter.
* One-way audio when a call is placed on hold
* Docker Compose prod-env was fixed.
* Call termination occurs when a DTMF digit is detected during the welcome announcement in the call queue

## Component changes

### OMLAPP (Django/VueJS)

* Container Img: https://hub.docker.com/layers/omnileads/omlapp/250424.01/images/sha256-90f8e560a5eb61157ea6442e1a6e9c5845f2898a6eef019c97f4e3ade6f1ca7f
* Gitlab Repo: https://gitlab.com/omnileads/ominicontacto/-/blob/250424.01/ReleaseNotes.md?ref_type=tags

### OMLACD (Automatic Call Distribution component)

* Container Img: https://hub.docker.com/layers/omnileads/asterisk/250422.01/images/sha256-fb123c2c89a630c0a14a54a617aa8ef74e20e1bf31565529653ef37388e5d999
* Gitlab Repo: https://gitlab.com/omnileads/omlacd/-/blob/250424.01/ReleasesNotes.md?ref_type=tags

### FASTAGI (ACD AGI endpoints)

* Container Img:  https://hub.docker.com/layers/omnileads/fastagi/250312.01/images/sha256-a16327f0021a42173c2a10fee42cdee4154fa71a75f65602cf8296e9669b8a06 
* Gitlab Repo: https://gitlab.com/omnileads/omlfastagi/-/blob/main/ReleaseNotes.md?ref_type=heads

### OMLMediaProxy (Media Proxy component)

* Container Img: https://hub.docker.com/layers/omnileads/rtpengine/240625.01/images/sha256-eb2148471eb89b3457988ed568d1260a961b1f52bfc2fa272a5cd85eb7d3a9c7
* Gitlab Repo: https://gitlab.com/omnileads/omlrtpengine/-/tree/240625.01?ref_type=tags

### OMLACDConfig (ACD config provisioner)

* Container Img: https://hub.docker.com/layers/omnileads/acd_retrieve_conf/250224.01/images/sha256-8d0c48581c3da220e6dceac74f60b54fc5addfd9b33db87216eff9d06182a198
* Gitlab Repo: https://gitlab.com/omnileads/acd_retrieve_conf/-/blob/main/ReleasesNotes.md?ref_type=heads

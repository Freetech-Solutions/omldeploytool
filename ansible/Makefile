ANSIBLE ?= ansible-playbook
INVENTORY ?= inventories/examples/inventory.yml
PLAYBOOK ?= playbooks/site.yml

.PHONY: collections lint syntax syntax-aio syntax-cluster

collections:
	ansible-galaxy collection install -r collections/requirements.yml -p ./collections

lint:
	ansible-lint \
		playbooks/site.yml \
		roles/topology_normalize \
		roles/observability_prometheus \
		roles/observability_promtail \
		roles/prerequisitos/tasks/checks_preflight.yml \
		roles/prerequisitos/tasks/checks_validate.yml

syntax:
	$(ANSIBLE) --syntax-check $(PLAYBOOK) -i $(INVENTORY)

syntax-aio:
	$(ANSIBLE) --syntax-check playbooks/aio.yml -i $(INVENTORY)

syntax-cluster:
	$(ANSIBLE) --syntax-check playbooks/cluster.yml -i $(INVENTORY)

.PHONY: multi-cluster-setup multi-cluster-add-cluster multi-cluster-delete-cluster multi-cluster-start-cluster multi-cluster-stop-cluster multi-cluster-start-base multi-cluster-stop-base

check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error $1$(if $2, ($2)) is not set. Set it by running `make $1$(if $2, ($2))=<value>`))

multi-cluster-setup:
	$(call check_defined, name)
	./multi_cluster/setup.sh $(name)

multi-cluster-add-cluster:
	$(call check_defined, name)
	./multi_cluster/cluster.sh add $(name)

multi-cluster-delete-cluster:
	$(call check_defined, name)
	./multi_cluster/cluster.sh delete $(name)

multi-cluster-start-cluster:
	$(call check_defined, name)
	./multi_cluster/cluster.sh start $(name)

multi-cluster-stop-cluster:
	$(call check_defined, name)
	./multi_cluster/cluster.sh stop $(name)

multi-cluster-start-base:
	./multi_cluster/base.sh start

multi-cluster-stop-base:
	./multi_cluster/base.sh stop

k ?= kubectl



clean:
	$(k) delete ns -R vault-secrets-operator || true
	$(k) delete ns -R tap || true
	#$(k) delete ns -R cachemachine || true
	$(k) delete ns -R mobu || true
	$(k) delete ns -R moneypenny || true
	$(k) delete ns -R nublado2 || true
	$(k) delete ns -R obstap || true
	$(k) delete ns -R portal || true
	$(k) delete ns -R squareone || true
	
	$(k) delete ns -R postgres || true
	$(k) delete ns -R gafaelfawr || true
	$(k) delete ns -R argo || true

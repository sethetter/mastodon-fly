.PHONY: deploy
deploy:
	fly deploy --region ord

.PHONY: pg-update
pg-update:
	fly image update -a sethetter-social-pg

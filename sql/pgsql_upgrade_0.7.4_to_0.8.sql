/*
 * Upgrade database schema.
 *
 * Copyright (C) 2010, Shaun Amott <shaun@inerd.com>
 * All rights reserved.
 *
 * $Id: pgsql_upgrade_0.7.4_to_0.8.sql,v 1.1 2010/05/24 02:35:02 samott Exp $
 */

DELETE
  FROM portscout;

INSERT
  INTO portscout (dbver)
VALUES (2010030301);

CREATE TABLE stats (
	key text,
	val text
);

CREATE
 INDEX sitedata_index_host
    ON sitedata (host);

CREATE
 INDEX moveddata_index_fromport
    ON moveddata (fromport);

/*
 * A value of zero will cause a full rebuild, but we need to
 * do this anyway, as there's a bug in 0.7.4 which means we
 * need to re-gather MASTER_SITES for certain ports.
 */

INSERT
  INTO stats (key, val)
VALUES ('buildtime', 0);

ALTER TABLE portdata DROP COLUMN dir;
ALTER TABLE portdata DROP COLUMN home;

ALTER TABLE portdata ADD COLUMN enslaved boolean;
ALTER TABLE portdata ALTER COLUMN enslaved SET DEFAULT FALSE;
UPDATE portdata SET enslaved = FALSE WHERE enslaved is NULL;

/*
 * Previous values are suspect due to a bug in 0.7.4.
 */

UPDATE sitedata SET liecount = 0;

/*
 * Upgrade database schema.
 *
 * Copyright (C) 2006-2008, Shaun Amott <shaun@inerd.com>
 * All rights reserved.
 *
 * $Id: pgsql_upgrade_0.7.3_to_0.7.4.sql,v 1.1 2008/01/24 04:10:35 samott Exp $
 */

DELETE
  FROM portscout;

INSERT
  INTO portscout (dbver)
VALUES (2008012301);

ALTER TABLE sitedata ADD COLUMN robots integer;
ALTER TABLE sitedata ALTER COLUMN robots SET DEFAULT 1;
UPDATE sitedata SET robots = 1 WHERE robots is NULL;

ALTER TABLE sitedata ADD COLUMN robots_paths text;
ALTER TABLE sitedata ALTER COLUMN robots_paths SET DEFAULT '';
UPDATE sitedata SET robots_paths = '' WHERE robots_paths is NULL;

ALTER TABLE sitedata ADD COLUMN robots_nextcheck timestamp;

/*
 * Upgrade database schema.
 *
 * Copyright (C) 2011, Shaun Amott <shaun@inerd.com>
 * All rights reserved.
 *
 * $Id: sqlite_upgrade_0.8_to_0.8.1.sql,v 1.1 2011/05/15 17:19:39 samott Exp $
 */

ALTER TABLE portdata ADD COLUMN discovered timestamp;

DELETE
  FROM portscout;

INSERT
  INTO portscout (dbver)
VALUES (2011040901);

CREATE
 INDEX portdata_index_discovered
    ON portdata (discovered);

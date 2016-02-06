/*
 * Upgrade database schema.
 *
 * Copyright (C) 2006-2007, Shaun Amott <shaun@inerd.com>
 * All rights reserved.
 *
 * $Id: pgsql_upgrade_0.7.1_to_0.7.2.sql,v 1.1 2007/02/02 23:03:04 samott Exp $
 */

DELETE
  FROM portscout;

INSERT
  INTO portscout (dbver)
VALUES (2007020201);

CREATE
 INDEX portdata_index_masterport_id
    ON portdata (masterport_id);

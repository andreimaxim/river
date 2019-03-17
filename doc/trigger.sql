BEGIN;

  CREATE OR REPLACE FUNCTION river.tg_river_notify()
    RETURNS TRIGGER
    LANGUAGE plpgsql
  AS $$
  DECLARE
    -- The channel used for notifications
    channel TEXT := TG_ARGV[0];
    -- The JSON object representing the previous contents of the row
    prev JSON;
    -- The JSON object representing the new contents of the row
    curr JSON;
  BEGIN

    /*
      Build the payload based on the type of operation.

      Postgres does provide two row objects, NEW and OLD, but they
      might be undefined based on the operation type (INSERT does not
      have an OLD and DELETE does not have a NEW).

      Also, keep in mind that a limitation of the `NOTIFY` command (or
      `pg_notify` function) is the maximum payload size of 8KB. If this
      is less than double the size of a serialized record (by default
      we send the previous values and the new values in the payload)
      consider altering the code with something like this:

        curr := json_build_object('id', NEW.id);
        prev := json_build_object('id', OLD.id);

      The client receiving the payload will then have to perform a query
      to extract the entire row.
    */
    IF TG_OP = 'INSERT' THEN
      curr := row_to_json(NEW);
      -- Set the previous row to empty JSON object
      prev := json_object('{}');
    ELSIF TG_OP = 'UPDATE' THEN
      curr := row_to_json(NEW);
      prev := row_to_json(OLD);
    ELSE
      -- Set the current row to empty JSON object
      curr := json_object('{}');
      prev := row_to_json(OLD);
    END IF;

    /*
      Generate a notification using the `pg_notify` function.

      The delivered notification is a JSON that looks like this:

        {
          "meta": { "table": "txns", "action": "INSERT", timestamp: ... },
          "data: {
            "curr": { <current payload if any> },
            "prev": { <previous payload if any> }
          }
        }

      This is the central point of the whole event-driven processing as it
      asynchronously generates a notification on the specified channel and
      from that point forward a different client can execute `LISTEN` on
      the specified channel and pick up those notifications.

      Do NOT change the code to run anything other than `pg_notify` as it
      can have a huge impact on performance, especially if you're doing
      any CPU or IO-intensive tasks.
    */
    PERFORM pg_notify(
      channel,
      json_build_object(
        -- Metadata that needs to be inserted into all events
        'meta', json_build_object(
          'table', TG_TABLE_NAME,
          'action', TG_OP,
          'timestamp', NOW()
        ),
        -- The new row data and the old row data
        'data', json_build_object('curr', curr, 'prev', prev)
      )::text
    );

    RETURN NULL;
  END;
$$;

-- Triggers do not have an `OR REPLACE` option so they need to be dropped first.
DROP TRIGGER IF EXISTS river_notify on river.txns;

/*
  The trigger that starts the entire notification event.

  There are a couple of things to keep in mind:

  1. It gets triggered at the end of a transaction
  2. It runs whenever it's an INSERT, UPDATE or DELETE
  3. It gets triggered for every changed row, even if it's just one statement
     that affects multiple rows (like a mass UPDATE).

  The trigger simply calls the previously defined procedure. Since Postgres
  creates the trigger at the table level, it needs to be defined on each table
  you want to watch (in this case it's the `river.txns` table). However,
  procedures are defined at the schema level so you do not need to redefine
  them.

  If you want to get notified of changes on a specific table on a different
  channel, just alter the parameter `river_events` to match whatever channel
  name you want.

  For example, if you want to get notified only on DELETEs on a `accounts`
  table you could write your trigger like this:

    CREATE TRIGGER river_notify
      AFTER DELETE
      ON postgres.accounts
      FOR EACH ROW
      EXECUTE PROCEDURE river.tg_river_notify('accounts_deleted');

  However, ideally, you'd want to keep the number of triggers to a minimum
  and handle this kind of logic in the client that's implementing the
  `LISTEN` command.
*/
CREATE TRIGGER river_notify
  AFTER INSERT OR UPDATE OR DELETE
  ON river.txns
  FOR EACH ROW
  EXECUTE PROCEDURE river.tg_river_notify('river_events');

COMMIT;

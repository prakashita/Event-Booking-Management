# Database migrations

Run migrations from the `Server` directory:

```bash
python -m migrations.run
```

Migrations are numbered scripts (`001_*.py`, `002_*.py`, ...). Each must define `async def upgrade(db)` where `db` is the Motor database. Applied migrations are tracked in the `migrations` collection.

To add a new migration: create `00N_description.py` with an `upgrade` function.

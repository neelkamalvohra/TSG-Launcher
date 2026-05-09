import psycopg2
conn = psycopg2.connect(host='postgres_n8n', port=5432, dbname='n8n_db', user='n8n_user', password='CHANGE_ME_n8n_pg_password')
cur = conn.cursor()

cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='workflow_entity' ORDER BY ordinal_position")
print("workflow_entity columns:", [r[0] for r in cur.fetchall()])

cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE '%workflow%'")
print("workflow tables:", [r[0] for r in cur.fetchall()])

# Check if there's a published nodes column
cur.execute("SELECT id, name, active, \"versionId\" FROM workflow_entity WHERE id = '19Qpg3xDx37sOvoM'")
row = cur.fetchone()
print("Workflow row (id, name, active, versionId):", row)

import psycopg2, json

conn = psycopg2.connect(host='postgres_n8n', port=5432, dbname='n8n_db', user='n8n_user', password='CHANGE_ME_n8n_pg_password')
cur = conn.cursor()

# Check workflow_published_version schema
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='workflow_published_version' ORDER BY ordinal_position")
print("workflow_published_version columns:", [r[0] for r in cur.fetchall()])

# Check if our workflow has a published version
cur.execute("SELECT * FROM workflow_published_version WHERE \"workflowId\" = '19Qpg3xDx37sOvoM'")
row = cur.fetchone()
if row:
    cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='workflow_published_version' ORDER BY ordinal_position")
    cols = [r[0] for r in cur.fetchall()]
    print("Published version exists. Columns:", cols)
    for col, val in zip(cols, row):
        if col != 'nodes':
            print(f"  {col}: {val}")
        else:
            nodes = val if isinstance(val, list) else json.loads(val)
            html_builder = next((n for n in nodes if n.get('name') == 'HTML Builder'), None)
            if html_builder:
                code = html_builder['parameters'].get('jsCode', '')
                print(f"  nodes[HTML Builder].jsCode (first 100): {code[:100]}")
else:
    print("No published version found for this workflow")

# Check activeVersionId vs versionId
cur.execute('SELECT "versionId", "activeVersionId" FROM workflow_entity WHERE id = \'19Qpg3xDx37sOvoM\'')
print("versionId vs activeVersionId:", cur.fetchone())

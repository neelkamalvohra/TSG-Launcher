import psycopg2, json

conn = psycopg2.connect(host='postgres_n8n', port=5432, dbname='n8n_db', user='n8n_user', password='CHANGE_ME_n8n_pg_password')
cur = conn.cursor()

# Check what's actually in workflow_entity.nodes for HTML Builder
cur.execute("SELECT nodes FROM workflow_entity WHERE id = '19Qpg3xDx37sOvoM'")
row = cur.fetchone()
nodes = row[0]
html_builder = next((n for n in nodes if n.get('name') == 'HTML Builder'), None)
if html_builder:
    code = html_builder['parameters'].get('jsCode', '')
    print("Current jsCode version line:", code.split('\n')[1] if '\n' in code else code[:80])
    print("Contains v3:", 'v3' in code)
    print("Contains overflow-x:hidden:", 'overflow-x:hidden' in code)
    print("Contains em-col:", 'em-col' in code)
    print("jsCode length:", len(code))

# Check workflow_history table columns
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='workflow_history' ORDER BY ordinal_position")
print("\nworkflow_history columns:", [r[0] for r in cur.fetchall()])

# Check if workflow_history has entries
cur.execute('SELECT COUNT(*) FROM workflow_history WHERE "workflowId" = \'19Qpg3xDx37sOvoM\'')
print("workflow_history entries:", cur.fetchone()[0])

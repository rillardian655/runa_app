import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://supabase.vantageos.my.id';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzQ5NjAwMDAwLCJleHAiOjE5MDczNjY0MDB9.mynZR8Jfv04jvitbB4MDFmN41j9kFsIw_xhjWBwIqNk';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function testInsert() {
  console.log("Testing RLS by inserting a fake user...");
  const { data, error } = await supabase
    .from('users')
    .insert([
      { uid: 'test_uid_123', email: 'test@example.com', username: 'testuser' }
    ])
    .select();

  if (error) {
    console.error("Failed to insert (RLS is active):", error.message);
  } else {
    console.log("Success! RLS allowed the insert:", data);
  }
}

testInsert();

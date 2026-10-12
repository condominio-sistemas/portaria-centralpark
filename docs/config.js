// Configuração do projeto Supabase (Project Settings → API Keys).
// Use a chave PÚBLICA ("publishable", sb_publishable_..., ou a antiga "anon").
// Ela é pública por natureza: a proteção dos dados é feita pelas regras do banco (RLS).
// NUNCA coloque aqui a chave secreta ("secret" / "service_role").
window.CONFIG = {
  SUPABASE_URL: 'https://SEU-PROJETO.supabase.co',
  SUPABASE_ANON_KEY: 'COLE-AQUI-A-CHAVE-PUBLICA',
  // domínio interno usado para transformar o nome de usuário em login do Supabase
  // (ex.: joao -> joao@portaria.local). Ninguém recebe e-mail nesse endereço.
  DOMINIO_USUARIOS: 'portaria.local'
};

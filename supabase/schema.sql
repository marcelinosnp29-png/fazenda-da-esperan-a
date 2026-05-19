-- ============================================================
-- SCHEMA COMPLETO - FAZENDA DA ESPERANÇA (CURSOS ONLINE)
-- Supabase SQL Editor
-- ============================================================

-- ------------------------------------------------------------
-- EXTENSÕES
-- ------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------
-- ENUM TYPES
-- ------------------------------------------------------------
CREATE TYPE user_role AS ENUM ('admin', 'aluno', 'instrutor');
CREATE TYPE post_status AS ENUM ('rascunho', 'publicado', 'arquivado');
CREATE TYPE lead_status AS ENUM ('novo', 'contatado', 'convertido', 'perdido');
CREATE TYPE arquivo_tipo AS ENUM ('imagem', 'video', 'documento', 'audio', 'outro');

-- ------------------------------------------------------------
-- TABELA: usuarios
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.usuarios (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL UNIQUE,
    nome        TEXT NOT NULL CHECK (char_length(nome) BETWEEN 2 AND 150),
    avatar_url  TEXT CHECK (avatar_url ~ '^https?://.*' OR avatar_url IS NULL),
    role        user_role NOT NULL DEFAULT 'aluno',
    telefone    TEXT CHECK (telefone ~ '^\+?[0-9\s\-\(\)]{7,20}$' OR telefone IS NULL),
    ativo       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.usuarios IS 'Perfis de usuários vinculados ao auth.users do Supabase';
COMMENT ON COLUMN public.usuarios.role IS 'admin | aluno | instrutor';

-- ------------------------------------------------------------
-- TABELA: leads
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.leads (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome        TEXT NOT NULL CHECK (char_length(nome) BETWEEN 2 AND 150),
    email       TEXT NOT NULL CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    telefone    TEXT CHECK (telefone ~ '^\+?[0-9\s\-\(\)]{7,20}$' OR telefone IS NULL),
    mensagem    TEXT CHECK (char_length(mensagem) <= 2000 OR mensagem IS NULL),
    origem      TEXT CHECK (char_length(origem) <= 100 OR origem IS NULL),
    status      lead_status NOT NULL DEFAULT 'novo',
    ip_address  INET,
    user_agent  TEXT CHECK (char_length(user_agent) <= 500 OR user_agent IS NULL),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.leads IS 'Leads capturados via formulários públicos';
COMMENT ON COLUMN public.leads.origem IS 'Ex: landing-page, popup, rodape';

-- ------------------------------------------------------------
-- TABELA: posts
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    titulo          TEXT NOT NULL CHECK (char_length(titulo) BETWEEN 3 AND 255),
    slug            TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    conteudo        TEXT,
    resumo          TEXT CHECK (char_length(resumo) <= 500 OR resumo IS NULL),
    capa_url        TEXT CHECK (capa_url ~ '^https?://.*' OR capa_url IS NULL),
    status          post_status NOT NULL DEFAULT 'rascunho',
    autor_id        UUID REFERENCES public.usuarios(id) ON DELETE SET NULL,
    tags            TEXT[] DEFAULT '{}',
    visualizacoes   INTEGER NOT NULL DEFAULT 0 CHECK (visualizacoes >= 0),
    publicado_em    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT publicado_em_obrigatorio
        CHECK (
            (status = 'publicado' AND publicado_em IS NOT NULL)
            OR status <> 'publicado'
        )
);

COMMENT ON TABLE public.posts IS 'Posts do blog / conteúdo dos cursos';
COMMENT ON COLUMN public.posts.slug IS 'URL amigável única, somente minúsculas e hífens';

-- Índices úteis
CREATE INDEX IF NOT EXISTS idx_posts_status     ON public.posts(status);
CREATE INDEX IF NOT EXISTS idx_posts_autor_id   ON public.posts(autor_id);
CREATE INDEX IF NOT EXISTS idx_posts_slug       ON public.posts(slug);
CREATE INDEX IF NOT EXISTS idx_posts_tags       ON public.posts USING GIN(tags);

-- ------------------------------------------------------------
-- TABELA: arquivos
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.arquivos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome            TEXT NOT NULL CHECK (char_length(nome) BETWEEN 1 AND 255),
    descricao       TEXT CHECK (char_length(descricao) <= 1000 OR descricao IS NULL),
    storage_path    TEXT NOT NULL CHECK (char_length(storage_path) >= 1),
    url_publica     TEXT CHECK (url_publica ~ '^https?://.*' OR url_publica IS NULL),
    tipo            arquivo_tipo NOT NULL DEFAULT 'outro',
    mime_type       TEXT CHECK (char_length(mime_type) <= 100 OR mime_type IS NULL),
    tamanho_bytes   BIGINT CHECK (tamanho_bytes > 0 OR tamanho_bytes IS NULL),
    post_id         UUID REFERENCES public.posts(id) ON DELETE SET NULL,
    enviado_por     UUID REFERENCES public.usuarios(id) ON DELETE SET NULL,
    publico         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.arquivos IS 'Metadados de arquivos armazenados no Supabase Storage';
COMMENT ON COLUMN public.arquivos.storage_path IS 'Caminho interno no bucket do Storage';

CREATE INDEX IF NOT EXISTS idx_arquivos_post_id     ON public.arquivos(post_id);
CREATE INDEX IF NOT EXISTS idx_arquivos_enviado_por ON public.arquivos(enviado_por);
CREATE INDEX IF NOT EXISTS idx_arquivos_tipo        ON public.arquivos(tipo);

-- ------------------------------------------------------------
-- TABELA: configuracoes
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.configuracoes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chave           TEXT NOT NULL UNIQUE CHECK (
                        char_length(chave) BETWEEN 1 AND 100
                        AND chave ~ '^[a-z][a-z0-9_]*$'
                    ),
    valor           TEXT CHECK (char_length(valor) <= 5000 OR valor IS NULL),
    descricao       TEXT CHECK (char_length(descricao) <= 500 OR descricao IS NULL),
    tipo            TEXT NOT NULL DEFAULT 'texto' CHECK (
                        tipo IN ('texto', 'numero', 'booleano', 'json', 'cor', 'url')
                    ),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.configuracoes IS 'Configurações globais da plataforma (chave-valor)';
COMMENT ON COLUMN public.configuracoes.tipo IS 'texto | numero | booleano | json | cor | url';

-- ------------------------------------------------------------
-- FUNÇÃO: atualizar updated_at automaticamente
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_set_updated_at IS
    'Atualiza o campo updated_at automaticamente em qualquer UPDATE';

-- Triggers updated_at
CREATE TRIGGER trg_usuarios_updated_at
    BEFORE UPDATE ON public.usuarios
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_leads_updated_at
    BEFORE UPDATE ON public.leads
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_posts_updated_at
    BEFORE UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_arquivos_updated_at
    BEFORE UPDATE ON public.arquivos
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_configuracoes_updated_at
    BEFORE UPDATE ON public.configuracoes
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ------------------------------------------------------------
-- FUNÇÃO + TRIGGER: handle_new_user (auth.users → public.usuarios)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nome TEXT;
BEGIN
    -- Tenta extrair nome do metadata, fallback para parte do e-mail
    v_nome := COALESCE(
        NEW.raw_user_meta_data->>'nome',
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'name',
        split_part(NEW.email, '@', 1)
    );

    -- Garante comprimento mínimo
    IF char_length(v_nome) < 2 THEN
        v_nome := v_nome || '_user';
    END IF;

    INSERT INTO public.usuarios (
        id,
        email,
        nome,
        avatar_url,
        role
    ) VALUES (
        NEW.id,
        NEW.email,
        v_nome,
        NEW.raw_user_meta_data->>'avatar_url',
        COALESCE(
            (NEW.raw_user_meta_data->>'role')::user_role,
            'aluno'::user_role
        )
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_handle_new_user IS
    'Cria automaticamente um registro em public.usuarios ao cadastrar em auth.users';

CREATE TRIGGER trg_auth_handle_new_user
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.fn_handle_new_user();

-- ------------------------------------------------------------
-- FUNÇÃO AUXILIAR: verificar se usuário é admin
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuarios
        WHERE id = auth.uid()
          AND role = 'admin'
          AND ativo = TRUE
    );
$$;

COMMENT ON FUNCTION public.fn_is_admin IS
    'Retorna TRUE se o usuário autenticado possuir role = admin';

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY — HABILITAR
-- ------------------------------------------------------------
ALTER TABLE public.usuarios        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arquivos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracoes   ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- POLÍTICAS RLS: usuarios
-- ============================================================

-- Admin: acesso total
CREATE POLICY "admin_all_usuarios"
    ON public.usuarios
    FOR ALL
    TO authenticated
    USING      (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- Usuário autenticado: lê/atualiza apenas seu próprio perfil
CREATE POLICY "usuario_select_proprio"
    ON public.usuarios
    FOR SELECT
    TO authenticated
    USING (id = auth.uid());

CREATE POLICY "usuario_update_proprio"
    ON public.usuarios
    FOR UPDATE
    TO authenticated
    USING      (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- ============================================================
-- POLÍTICAS RLS: leads
-- ============================================================

-- Anônimo e autenticado: pode inserir lead
CREATE POLICY "anonimo_insert_lead"
    ON public.leads
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (TRUE);

-- Admin: acesso total
CREATE POLICY "admin_all_leads"
    ON public.leads
    FOR ALL
    TO authenticated
    USING      (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS: posts
-- ============================================================

-- Público (anônimo e autenticado): lê apenas posts publicados
CREATE POLICY "publico_select_posts_publicados"
    ON public.posts
    FOR SELECT
    TO anon, authenticated
    USING (status = 'publicado');

-- Instrutor/admin: lê todos os seus próprios posts
CREATE POLICY "autor_select_proprio_post"
    ON public.posts
    FOR SELECT
    TO authenticated
    USING (autor_id = auth.uid());

-- Instrutor: cria posts (autor = si mesmo)
CREATE POLICY "instrutor_insert_post"
    ON public.posts
    FOR INSERT
    TO authenticated
    WITH CHECK (
        autor_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.usuarios
            WHERE id = auth.uid()
              AND role IN ('admin', 'instrutor')
              AND ativo = TRUE
        )
    );

-- Instrutor: atualiza seus próprios posts
CREATE POLICY "autor_update_proprio_post"
    ON public.posts
    FOR UPDATE
    TO authenticated
    USING (
        autor_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.usuarios
            WHERE id = auth.uid()
              AND role IN ('admin', 'instrutor')
              AND ativo = TRUE
        )
    )
    WITH CHECK (autor_id = auth.uid());

-- Admin: acesso total
CREATE POLICY "admin_all_posts"
    ON public.posts
    FOR ALL
    TO authenticated
    USING      (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS: arquivos
-- ============================================================

-- Público: lê arquivos marcados como públicos
CREATE POLICY "publico_select_arquivos_publicos"
    ON public.arquivos
    FOR SELECT
    TO anon, authenticated
    USING (publico = TRUE);

-- Usuário autenticado: lê arquivos que ele enviou
CREATE POLICY "usuario_select_proprio_arquivo"
    ON public.arquivos
    FOR SELECT
    TO authenticated
    USING (enviado_por = auth.uid());

-- Usuário autenticado: faz upload (INSERT)
CREATE POLICY "usuario_insert_arquivo"
    ON public.arquivos
    FOR INSERT
    TO authenticated
    WITH CHECK (enviado_por = auth.uid());

-- Usuário autenticado: atualiza/deleta seus próprios arquivos
CREATE POLICY "usuario_update_proprio_arquivo"
    ON public.arquivos
    FOR UPDATE
    TO authenticated
    USING      (enviado_por = auth.uid())
    WITH CHECK (enviado_por = auth.uid());

CREATE POLICY "usuario_delete_proprio_arquivo"
    ON public.arquivos
    FOR DELETE
    TO authenticated
    USING (enviado_por = auth.uid());

-- Admin: acesso total
CREATE POLICY "admin_all_arquivos"
    ON public.arquivos
    FOR ALL
    TO authenticated
    USING      (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS: configuracoes
-- ============================================================

-- Qualquer um (anon + autenticado): lê configurações
CREATE POLICY "publico_select_configuracoes"
    ON public.configuracoes
    FOR SELECT
    TO anon, authenticated
    USING (TRUE);

-- Admin: acesso total (INSERT / UPDATE / DELETE)
CREATE POLICY "admin_all_configuracoes"
    ON public.configuracoes
    FOR ALL
    TO authenticated
    USING      (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- ------------------------------------------------------------
-- INSERT INICIAL: configuracoes
-- ------------------------------------------------------------
INSERT INTO public.configuracoes (chave, valor, descricao, tipo) VALUES
    ('nome_empresa',    'Fazenda da Esperança',  'Nome exibido na plataforma e e-mails',         'texto'),
    ('cor_primaria',    '#2563eb',               'Cor primária da interface (hex)',               'cor'),
    ('cor_secundaria',  '#1e40af',               'Cor secundária da interface (hex)',             'cor'),
    ('whatsapp',        '+5511999999999',         'Número WhatsApp para contato e suporte',        'texto'),
    ('email_suporte',   'suporte@fazendaesperanca.com.br', 'E-mail de suporte ao aluno',          'texto'),
    ('site_url',        'https://fazendaesperanca.com.br', 'URL pública da plataforma',           'url'),
    ('logo_url',        NULL,                    'URL do logotipo principal',                     'url'),
    ('favicon_url',     NULL,                    'URL do favicon',                                'url'),
    ('manutencao',      'false',                 'Ativa modo manutenção (true/false)',             'booleano'),
    ('max_upload_mb',   '50',                    'Tamanho máximo de upload em MB',                'numero')
ON CONFLICT (chave) DO NOTHING;

-- ------------------------------------------------------------
-- GRANT DE EXECUÇÃO DAS FUNÇÕES PARA ROLES
-- ------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.fn_set_updated_at   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_handle_new_user  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_is_admin         TO authenticated, anon;

-- ------------------------------------------------------------
-- VERIFICAÇÃO FINAL (opcional — retorna resumo das tabelas)
-- ------------------------------------------------------------
SELECT
    schemaname,
    tablename,
    rowsecurity AS rls_ativo
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('usuarios','leads','posts','arquivos','configuracoes')
ORDER BY tablename;
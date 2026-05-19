-- ============================================================
-- SCHEMA COMPLETO — FAZENDA DA ESPERANÇA (CURSOS ON-LINE)
-- Supabase SQL Editor
-- ============================================================

-- ------------------------------------------------------------
-- EXTENSÕES
-- ------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- TABELAS
-- ============================================================

-- ------------------------------------------------------------
-- 1. LEADS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.leads (
    id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome          TEXT        NOT NULL CHECK (char_length(nome) BETWEEN 2 AND 150),
    email         TEXT        NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'),
    telefone      TEXT        CHECK (telefone IS NULL OR char_length(telefone) BETWEEN 8 AND 20),
    origem        TEXT        NOT NULL DEFAULT 'site'
                              CHECK (origem IN ('site','landing_page','indicacao','social','outro')),
    interesse     TEXT,
    mensagem      TEXT        CHECK (mensagem IS NULL OR char_length(mensagem) <= 2000),
    status        TEXT        NOT NULL DEFAULT 'novo'
                              CHECK (status IN ('novo','contatado','qualificado','convertido','descartado')),
    ip_origem     INET,
    utm_source    TEXT,
    utm_medium    TEXT,
    utm_campaign  TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 2. USUÁRIOS (espelho de auth.users + dados extras)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.usuarios (
    id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nome          TEXT        NOT NULL CHECK (char_length(nome) BETWEEN 2 AND 150),
    email         TEXT        NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'),
    avatar_url    TEXT        CHECK (avatar_url IS NULL OR char_length(avatar_url) <= 500),
    bio           TEXT        CHECK (bio IS NULL OR char_length(bio) <= 1000),
    telefone      TEXT        CHECK (telefone IS NULL OR char_length(telefone) BETWEEN 8 AND 20),
    role          TEXT        NOT NULL DEFAULT 'aluno'
                              CHECK (role IN ('admin','instrutor','aluno')),
    ativo         BOOLEAN     NOT NULL DEFAULT TRUE,
    ultimo_acesso TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 3. POSTS (artigos / aulas / notícias)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts (
    id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    autor_id       UUID        NOT NULL REFERENCES public.usuarios(id) ON DELETE SET NULL,
    titulo         TEXT        NOT NULL CHECK (char_length(titulo) BETWEEN 3 AND 250),
    slug           TEXT        NOT NULL UNIQUE CHECK (slug ~* '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    resumo         TEXT        CHECK (resumo IS NULL OR char_length(resumo) <= 500),
    conteudo       TEXT        NOT NULL CHECK (char_length(conteudo) >= 10),
    imagem_capa    TEXT        CHECK (imagem_capa IS NULL OR char_length(imagem_capa) <= 500),
    categoria      TEXT        NOT NULL DEFAULT 'geral'
                               CHECK (categoria IN ('geral','curso','noticia','devocional','evento','outro')),
    tags           TEXT[]      DEFAULT '{}',
    status         TEXT        NOT NULL DEFAULT 'rascunho'
                               CHECK (status IN ('rascunho','revisao','publicado','arquivado')),
    destaque       BOOLEAN     NOT NULL DEFAULT FALSE,
    visualizacoes  INTEGER     NOT NULL DEFAULT 0 CHECK (visualizacoes >= 0),
    publicado_em   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 4. CONFIGURAÇÕES
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.configuracoes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    chave           TEXT        NOT NULL UNIQUE CHECK (char_length(chave) BETWEEN 2 AND 100),
    valor           TEXT        CHECK (valor IS NULL OR char_length(valor) <= 5000),
    tipo            TEXT        NOT NULL DEFAULT 'texto'
                                CHECK (tipo IN ('texto','numero','booleano','json','cor','url')),
    descricao       TEXT        CHECK (descricao IS NULL OR char_length(descricao) <= 500),
    editavel        BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 5. ARQUIVOS (storage metadata)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.arquivos (
    id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id    UUID        REFERENCES public.usuarios(id) ON DELETE SET NULL,
    post_id       UUID        REFERENCES public.posts(id) ON DELETE SET NULL,
    nome_original TEXT        NOT NULL CHECK (char_length(nome_original) BETWEEN 1 AND 255),
    nome_storage  TEXT        NOT NULL UNIQUE CHECK (char_length(nome_storage) BETWEEN 1 AND 500),
    bucket        TEXT        NOT NULL DEFAULT 'arquivos'
                              CHECK (char_length(bucket) BETWEEN 1 AND 100),
    mime_type     TEXT        NOT NULL CHECK (char_length(mime_type) BETWEEN 3 AND 100),
    tamanho_bytes BIGINT      NOT NULL CHECK (tamanho_bytes > 0),
    url_publica   TEXT        CHECK (url_publica IS NULL OR char_length(url_publica) <= 1000),
    tipo          TEXT        NOT NULL DEFAULT 'documento'
                              CHECK (tipo IN ('imagem','video','audio','documento','outro')),
    publico       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ÍNDICES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_leads_email       ON public.leads(email);
CREATE INDEX IF NOT EXISTS idx_leads_status      ON public.leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_created_at  ON public.leads(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_usuarios_email    ON public.usuarios(email);
CREATE INDEX IF NOT EXISTS idx_usuarios_role     ON public.usuarios(role);

CREATE INDEX IF NOT EXISTS idx_posts_slug        ON public.posts(slug);
CREATE INDEX IF NOT EXISTS idx_posts_status      ON public.posts(status);
CREATE INDEX IF NOT EXISTS idx_posts_autor       ON public.posts(autor_id);
CREATE INDEX IF NOT EXISTS idx_posts_categoria   ON public.posts(categoria);
CREATE INDEX IF NOT EXISTS idx_posts_publicado   ON public.posts(publicado_em DESC);

CREATE INDEX IF NOT EXISTS idx_configuracoes_chave ON public.configuracoes(chave);

CREATE INDEX IF NOT EXISTS idx_arquivos_usuario  ON public.arquivos(usuario_id);
CREATE INDEX IF NOT EXISTS idx_arquivos_post     ON public.arquivos(post_id);
CREATE INDEX IF NOT EXISTS idx_arquivos_tipo     ON public.arquivos(tipo);

-- ============================================================
-- FUNÇÕES AUXILIARES
-- ============================================================

-- ------------------------------------------------------------
-- Função genérica: atualiza updated_at automaticamente
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

-- ------------------------------------------------------------
-- Função: cria registro em public.usuarios ao criar auth.user
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_nome  TEXT;
    v_email TEXT;
BEGIN
    v_email := NEW.email;

    -- Tenta pegar o nome dos metadados; usa parte do e-mail como fallback
    v_nome := COALESCE(
        NEW.raw_user_meta_data->>'nome',
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'name',
        split_part(v_email, '@', 1)
    );

    INSERT INTO public.usuarios (id, nome, email, role, ativo, created_at, updated_at)
    VALUES (
        NEW.id,
        v_nome,
        v_email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'aluno'),
        TRUE,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger: novo usuário em auth.users → public.usuarios
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Trigger: updated_at → leads
DROP TRIGGER IF EXISTS trg_leads_updated_at ON public.leads;
CREATE TRIGGER trg_leads_updated_at
    BEFORE UPDATE ON public.leads
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();

-- Trigger: updated_at → usuarios
DROP TRIGGER IF EXISTS trg_usuarios_updated_at ON public.usuarios;
CREATE TRIGGER trg_usuarios_updated_at
    BEFORE UPDATE ON public.usuarios
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();

-- Trigger: updated_at → posts
DROP TRIGGER IF EXISTS trg_posts_updated_at ON public.posts;
CREATE TRIGGER trg_posts_updated_at
    BEFORE UPDATE ON public.posts
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();

-- Trigger: updated_at → configuracoes
DROP TRIGGER IF EXISTS trg_configuracoes_updated_at ON public.configuracoes;
CREATE TRIGGER trg_configuracoes_updated_at
    BEFORE UPDATE ON public.configuracoes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();

-- Trigger: updated_at → arquivos
DROP TRIGGER IF EXISTS trg_arquivos_updated_at ON public.arquivos;
CREATE TRIGGER trg_arquivos_updated_at
    BEFORE UPDATE ON public.arquivos
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.leads         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arquivos      ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- Função auxiliar: verifica se o usuário logado é admin
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
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

-- ------------------------------------------------------------
-- Função auxiliar: verifica se o usuário logado é instrutor ou admin
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_is_instrutor_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuarios
        WHERE id = auth.uid()
          AND role IN ('admin','instrutor')
          AND ativo = TRUE
    );
$$;

-- ============================================================
-- POLÍTICAS RLS — LEADS
-- ============================================================

-- Qualquer pessoa (inclusive anônima) pode inserir um lead
CREATE POLICY "leads_insert_anonimo"
    ON public.leads FOR INSERT
    TO anon, authenticated
    WITH CHECK (TRUE);

-- Apenas admin visualiza / edita / remove leads
CREATE POLICY "leads_select_admin"
    ON public.leads FOR SELECT
    TO authenticated
    USING (public.fn_is_admin());

CREATE POLICY "leads_update_admin"
    ON public.leads FOR UPDATE
    TO authenticated
    USING (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

CREATE POLICY "leads_delete_admin"
    ON public.leads FOR DELETE
    TO authenticated
    USING (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS — USUÁRIOS
-- ============================================================

-- Usuário autenticado vê seu próprio registro
CREATE POLICY "usuarios_select_proprio"
    ON public.usuarios FOR SELECT
    TO authenticated
    USING (id = auth.uid());

-- Admin vê todos
CREATE POLICY "usuarios_select_admin"
    ON public.usuarios FOR SELECT
    TO authenticated
    USING (public.fn_is_admin());

-- Usuário atualiza apenas seu próprio registro
CREATE POLICY "usuarios_update_proprio"
    ON public.usuarios FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Admin atualiza qualquer registro
CREATE POLICY "usuarios_update_admin"
    ON public.usuarios FOR UPDATE
    TO authenticated
    USING (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

-- Admin remove usuários
CREATE POLICY "usuarios_delete_admin"
    ON public.usuarios FOR DELETE
    TO authenticated
    USING (public.fn_is_admin());

-- INSERT feito apenas via trigger (handle_new_user) com SECURITY DEFINER
-- Política para garantir que o trigger possa inserir:
CREATE POLICY "usuarios_insert_trigger"
    ON public.usuarios FOR INSERT
    TO authenticated
    WITH CHECK (id = auth.uid() OR public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS — POSTS
-- ============================================================

-- Qualquer pessoa (anon + autenticado) lê posts publicados
CREATE POLICY "posts_select_publico"
    ON public.posts FOR SELECT
    TO anon, authenticated
    USING (status = 'publicado');

-- Instrutor/admin lê todos os posts
CREATE POLICY "posts_select_instrutor"
    ON public.posts FOR SELECT
    TO authenticated
    USING (public.fn_is_instrutor_or_admin());

-- Instrutor insere post (como próprio autor)
CREATE POLICY "posts_insert_instrutor"
    ON public.posts FOR INSERT
    TO authenticated
    WITH CHECK (
        public.fn_is_instrutor_or_admin()
        AND autor_id = auth.uid()
    );

-- Autor edita seu próprio post; admin edita qualquer um
CREATE POLICY "posts_update_autor_ou_admin"
    ON public.posts FOR UPDATE
    TO authenticated
    USING (autor_id = auth.uid() OR public.fn_is_admin())
    WITH CHECK (autor_id = auth.uid() OR public.fn_is_admin());

-- Apenas admin remove posts
CREATE POLICY "posts_delete_admin"
    ON public.posts FOR DELETE
    TO authenticated
    USING (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS — CONFIGURAÇÕES
-- ============================================================

-- Qualquer pessoa lê configurações (dados públicos do site)
CREATE POLICY "configuracoes_select_publico"
    ON public.configuracoes FOR SELECT
    TO anon, authenticated
    USING (TRUE);

-- Apenas admin insere / atualiza / remove configurações
CREATE POLICY "configuracoes_insert_admin"
    ON public.configuracoes FOR INSERT
    TO authenticated
    WITH CHECK (public.fn_is_admin());

CREATE POLICY "configuracoes_update_admin"
    ON public.configuracoes FOR UPDATE
    TO authenticated
    USING (public.fn_is_admin())
    WITH CHECK (public.fn_is_admin());

CREATE POLICY "configuracoes_delete_admin"
    ON public.configuracoes FOR DELETE
    TO authenticated
    USING (public.fn_is_admin());

-- ============================================================
-- POLÍTICAS RLS — ARQUIVOS
-- ============================================================

-- Arquivos públicos são visíveis por todos
CREATE POLICY "arquivos_select_publico"
    ON public.arquivos FOR SELECT
    TO anon, authenticated
    USING (publico = TRUE);

-- Usuário autenticado vê seus próprios arquivos
CREATE POLICY "arquivos_select_proprio"
    ON public.arquivos FOR SELECT
    TO authenticated
    USING (usuario_id = auth.uid());

-- Admin vê todos os arquivos
CREATE POLICY "arquivos_select_admin"
    ON public.arquivos FOR SELECT
    TO authenticated
    USING (public.fn_is_admin());

-- Usuário autenticado insere seus próprios arquivos
CREATE POLICY "arquivos_insert_autenticado"
    ON public.arquivos FOR INSERT
    TO authenticated
    WITH CHECK (usuario_id = auth.uid() OR public.fn_is_admin());

-- Usuário atualiza seus próprios arquivos; admin atualiza todos
CREATE POLICY "arquivos_update_proprio_ou_admin"
    ON public.arquivos FOR UPDATE
    TO authenticated
    USING (usuario_id = auth.uid() OR public.fn_is_admin())
    WITH CHECK (usuario_id = auth.uid() OR public.fn_is_admin());

-- Usuário remove seus próprios arquivos; admin remove todos
CREATE POLICY "arquivos_delete_proprio_ou_admin"
    ON public.arquivos FOR DELETE
    TO authenticated
    USING (usuario_id = auth.uid() OR public.fn_is_admin());

-- ============================================================
-- DADOS INICIAIS — CONFIGURAÇÕES
-- ============================================================

INSERT INTO public.configuracoes (chave, valor, tipo, descricao, editavel)
VALUES
    ('nome_empresa',      'Fazenda da Esperança',  'texto', 'Nome exibido no site e e-mails',              TRUE),
    ('cor_primaria',      '#2563eb',               'cor',   'Cor primária da identidade visual (hex)',      TRUE),
    ('cor_secundaria',    '#1e40af',               'cor',   'Cor secundária da identidade visual (hex)',    TRUE),
    ('whatsapp',          '+5511999999999',         'texto', 'Número WhatsApp para contato (com DDI)',       TRUE),
    ('email_contato',     'contato@fazendaesperanca.org.br', 'texto', 'E-mail principal de contato',        TRUE),
    ('site_url',          'https://fazendaesperanca.org.br', 'url',   'URL pública do site',                TRUE),
    ('logo_url',          NULL,                    'url',   'URL da logo principal',                        TRUE),
    ('favicon_url',       NULL,                    'url',   'URL do favicon',                               TRUE),
    ('descricao_site',    'Cursos on-line da Fazenda da Esperança', 'texto', 'Meta description padrão',     TRUE),
    ('manutencao',        'false',                 'booleano', 'Ativa modo manutenção no site',             TRUE),
    ('max_upload_mb',     '50',                    'numero',   'Tamanho máximo de upload em MB',            TRUE),
    ('smtp_host',         NULL,                    'texto', 'Host SMTP para envio de e-mails',              TRUE),
    ('smtp_porta',        '587',                   'numero','Porta SMTP',                                   TRUE),
    ('redes_sociais',     '{"instagram":"","facebook":"","youtube":""}',
                                                   'json',  'Links das redes sociais (JSON)',               TRUE)
ON CONFLICT (chave) DO UPDATE
    SET valor      = EXCLUDED.valor,
        tipo       = EXCLUDED.tipo,
        descricao  = EXCLUDED.descricao,
        updated_at = NOW();

-- ============================================================
-- FIM DO SCHEMA
-- ============================================================
-- Последовательности для bigint таблиц
CREATE SEQUENCE IF NOT EXISTS admin_digest_runs_id_seq;
CREATE SEQUENCE IF NOT EXISTS admin_warning_state_id_seq;
CREATE SEQUENCE IF NOT EXISTS admin_digest_http_log_id_seq;

CREATE TABLE public.work_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_name text NOT NULL,
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  total_hours numeric,
  address_start text,
  address_end text,
  pay_rate numeric,
  total_payment numeric,
  user_id uuid,
  payment_status text DEFAULT 'PENDING'::text,
  paid_at timestamp with time zone,
  CONSTRAINT work_logs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.workers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  role text NOT NULL,
  hourly_rate numeric NOT NULL DEFAULT 0,
  avatar_url text,
  auth_user_id uuid UNIQUE,
  name text,
  hourly_rate_updated_at timestamp with time zone DEFAULT now(),
  hourly_rate_updated_by uuid DEFAULT auth.uid(),
  is_active boolean DEFAULT true,
  last_activity timestamp with time zone,
  on_shift boolean DEFAULT false,
  access_mode text NOT NULL DEFAULT 'worker'::text,
  owner_admin_id uuid,
  last_work_at timestamp with time zone,
  suspended_at timestamp with time zone,
  view_only_at timestamp with time zone,
  created_by_auth_id uuid,
  can_view_address boolean NOT NULL DEFAULT false,
  in_app boolean NOT NULL DEFAULT false,
  last_seen_at timestamp with time zone,
  CONSTRAINT workers_pkey PRIMARY KEY (id),
  CONSTRAINT workers_auth_user_fk FOREIGN KEY (auth_user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.shift_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  worker_id uuid NOT NULL,
  worker_email text,
  event_type text NOT NULL,
  address_text text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT shift_events_pkey PRIMARY KEY (id)
);
CREATE TABLE public.admin_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_email text NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT admin_settings_pkey PRIMARY KEY (id)
);
CREATE TABLE public.payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  worker_auth_id uuid NOT NULL,
  admin_email text NOT NULL,
  period_from timestamp with time zone NOT NULL,
  period_to timestamp with time zone NOT NULL,
  total_hours numeric NOT NULL,
  total_amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  payment_method text NOT NULL DEFAULT 'cash'::text CHECK (payment_method = ANY (ARRAY['cash'::text, 'card'::text, 'transfer'::text, 'check'::text, 'other'::text])),
  payment_note text,
  CONSTRAINT payments_pkey PRIMARY KEY (id),
  CONSTRAINT payments_worker_auth_id_fkey FOREIGN KEY (worker_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.payment_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL,
  work_log_id uuid NOT NULL,
  amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT payment_items_pkey PRIMARY KEY (id),
  CONSTRAINT payment_items_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id),
  CONSTRAINT payment_items_work_log_id_fkey FOREIGN KEY (work_log_id) REFERENCES public.work_logs(id)
);
CREATE TABLE public.worker_rate_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  worker_id uuid NOT NULL,
  old_rate numeric NOT NULL,
  new_rate numeric NOT NULL,
  changed_at timestamp with time zone NOT NULL DEFAULT now(),
  changed_by uuid,
  note text,
  CONSTRAINT worker_rate_history_pkey PRIMARY KEY (id),
  CONSTRAINT worker_rate_history_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(id)
);
CREATE TABLE public.admin_users (
  email text NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT admin_users_pkey PRIMARY KEY (email)
);
CREATE TABLE public.admin_digest_runs (
  id bigint NOT NULL DEFAULT nextval('admin_digest_runs_id_seq'::regclass),
  ran_at timestamp with time zone NOT NULL DEFAULT now(),
  request_id bigint,
  response jsonb,
  CONSTRAINT admin_digest_runs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.admin_alert_state (
  admin_id uuid NOT NULL,
  alert_key text NOT NULL,
  signature text NOT NULL,
  level text NOT NULL CHECK (level = ANY (ARRAY['critical'::text, 'warning'::text])),
  first_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  last_sent_at timestamp with time zone,
  acked_at timestamp with time zone,
  acked_signature text,
  muted_until timestamp with time zone,
  resolved_at timestamp with time zone,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT admin_alert_state_pkey PRIMARY KEY (admin_id, alert_key)
);
CREATE TABLE public.admin_warning_state (
  id bigint NOT NULL DEFAULT nextval('admin_warning_state_id_seq'::regclass),
  admin_id uuid NOT NULL,
  warning_key text NOT NULL,
  warning_type text NOT NULL,
  fingerprint text NOT NULL,
  first_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  last_sent_at timestamp with time zone,
  resolved_at timestamp with time zone,
  muted_until timestamp with time zone,
  muted_forever boolean NOT NULL DEFAULT false,
  ack_at timestamp with time zone,
  ack_expires_at timestamp with time zone,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT admin_warning_state_pkey PRIMARY KEY (id)
);
CREATE TABLE public.admin_digest_http_log (
  id bigint NOT NULL DEFAULT nextval('admin_digest_http_log_id_seq'::regclass),
  req_id bigint NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT admin_digest_http_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.worker_tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  worker_id uuid NOT NULL,
  worker_auth_id uuid NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) >= 1 AND char_length(btrim(title)) <= 160),
  description text,
  status text NOT NULL DEFAULT 'todo'::text CHECK (status = ANY (ARRAY['todo'::text, 'in_progress'::text, 'done'::text, 'needs_review'::text, 'cancelled'::text])),
  priority text NOT NULL DEFAULT 'normal'::text CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  due_at timestamp with time zone,
  completed_at timestamp with time zone,
  worker_note text,
  sort_order integer NOT NULL DEFAULT 0,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  worker_acknowledged_at timestamp with time zone,
  CONSTRAINT worker_tasks_pkey PRIMARY KEY (id),
  CONSTRAINT worker_tasks_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(id)
);
CREATE TABLE public.task_subtasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  title text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_done boolean NOT NULL DEFAULT false,
  done_at timestamp with time zone,
  done_by_auth_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  status text NOT NULL DEFAULT 'todo'::text CHECK (status = ANY (ARRAY['todo'::text, 'done'::text, 'blocked'::text, 'not_needed'::text, 'partial'::text])),
  status_note text,
  status_updated_at timestamp with time zone,
  status_set_by_auth_id uuid,
  CONSTRAINT task_subtasks_pkey PRIMARY KEY (id),
  CONSTRAINT task_subtasks_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.worker_tasks(id),
  CONSTRAINT task_subtasks_status_set_by_auth_id_fkey FOREIGN KEY (status_set_by_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.task_attachments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  uploaded_by_auth_id uuid NOT NULL,
  uploaded_by_role text NOT NULL CHECK (uploaded_by_role = ANY (ARRAY['admin'::text, 'worker'::text])),
  attachment_type text NOT NULL CHECK (attachment_type = ANY (ARRAY['image'::text, 'file'::text])),
  media_url text NOT NULL,
  media_path text NOT NULL,
  file_name text,
  mime_type text,
  file_size bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  proof_subtask_id uuid,
  proof_kind text,
  proof_meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT task_attachments_pkey PRIMARY KEY (id),
  CONSTRAINT task_attachments_proof_subtask_id_fkey FOREIGN KEY (proof_subtask_id) REFERENCES public.task_subtasks(id),
  CONSTRAINT task_attachments_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.worker_tasks(id)
);
CREATE TABLE public.task_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  actor_auth_id uuid NOT NULL,
  actor_role text NOT NULL CHECK (actor_role = ANY (ARRAY['admin'::text, 'worker'::text])),
  event_type text NOT NULL CHECK (event_type = ANY (ARRAY['task_created'::text, 'task_updated'::text, 'title_changed'::text, 'description_changed'::text, 'priority_changed'::text, 'due_changed'::text, 'status_changed'::text, 'sort_changed'::text, 'archive_changed'::text, 'note_changed'::text, 'checklist_changed'::text, 'subtask_toggled'::text, 'subtask_status_changed'::text, 'worker_task_updated'::text, 'attachment_added'::text, 'photo_added'::text, 'file_added'::text])),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  seen_by_admin_at timestamp with time zone,
  seen_by_worker_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT task_events_pkey PRIMARY KEY (id),
  CONSTRAINT task_events_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.worker_tasks(id)
);
CREATE TABLE public.messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL,
  sender_auth_id uuid NOT NULL,
  sender_role text NOT NULL CHECK (sender_role = ANY (ARRAY['admin'::text, 'worker'::text])),
  body text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  read_at timestamp with time zone,
  message_type text NOT NULL DEFAULT 'text'::text CHECK (message_type = ANY (ARRAY['text'::text, 'image'::text, 'file'::text])),
  media_url text,
  media_path text,
  file_name text,
  mime_type text,
  file_size bigint,
  edited_at timestamp with time zone,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  reply_to_message_id uuid,
  CONSTRAINT messages_pkey PRIMARY KEY (id),
  CONSTRAINT messages_reply_to_message_id_fkey FOREIGN KEY (reply_to_message_id) REFERENCES public.messages(id)
);
CREATE TABLE public.message_threads (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  worker_id uuid NOT NULL,
  worker_auth_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  last_message_at timestamp with time zone NOT NULL DEFAULT now(),
  pinned_message_id uuid,
  pinned_at timestamp with time zone,
  pinned_by uuid,
  CONSTRAINT message_threads_pkey PRIMARY KEY (id),
  CONSTRAINT message_threads_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(id),
  CONSTRAINT message_threads_pinned_message_id_fkey FOREIGN KEY (pinned_message_id) REFERENCES public.messages(id)
);
-- Add FK for messages.thread_id after message_threads exists
ALTER TABLE public.messages ADD CONSTRAINT messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.message_threads(id);
CREATE TABLE public.admin_calendar_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  entry_date date NOT NULL,
  kind text NOT NULL CHECK (kind = ANY (ARRAY['note'::text, 'reminder'::text])),
  title text,
  note_text text NOT NULL DEFAULT ''::text,
  reminder_at timestamp with time zone,
  notify_in_app boolean NOT NULL DEFAULT false,
  is_sent boolean NOT NULL DEFAULT false,
  is_done boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  is_cancelled boolean NOT NULL DEFAULT false,
  CONSTRAINT admin_calendar_items_pkey PRIMARY KEY (id),
  CONSTRAINT admin_calendar_items_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id)
);
CREATE TABLE public.admin_calendar_delivery_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL,
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  channel text NOT NULL DEFAULT 'in_app'::text,
  CONSTRAINT admin_calendar_delivery_log_pkey PRIMARY KEY (id),
  CONSTRAINT admin_calendar_delivery_log_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.admin_calendar_items(id)
);
CREATE TABLE public.admin_in_app_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  calendar_item_id uuid NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT admin_in_app_notifications_pkey PRIMARY KEY (id),
  CONSTRAINT admin_in_app_notifications_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id),
  CONSTRAINT admin_in_app_notifications_calendar_item_id_fkey FOREIGN KEY (calendar_item_id) REFERENCES public.admin_calendar_items(id)
);
CREATE TABLE public.admin_push_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  token text NOT NULL UNIQUE,
  platform text NOT NULL DEFAULT 'android'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT admin_push_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT admin_push_tokens_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id)
);
CREATE TABLE public.clients (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  full_name text NOT NULL,
  phone text,
  email text,
  company_name text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  is_archived boolean NOT NULL DEFAULT false,
  CONSTRAINT clients_pkey PRIMARY KEY (id),
  CONSTRAINT clients_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.properties (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  client_id uuid NOT NULL,
  address_line_1 text NOT NULL,
  address_line_2 text,
  city text,
  province text,
  postal_code text,
  square_footage numeric DEFAULT 0,
  property_type text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  is_archived boolean NOT NULL DEFAULT false,
  CONSTRAINT properties_pkey PRIMARY KEY (id),
  CONSTRAINT properties_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id),
  CONSTRAINT properties_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id)
);
CREATE TABLE public.estimates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  client_id uuid NOT NULL,
  property_id uuid NOT NULL,
  estimate_number text NOT NULL,
  title text NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'approved'::text, 'rejected'::text, 'archived'::text])),
  scope_text text,
  notes text,
  subtotal numeric NOT NULL DEFAULT 0,
  tax numeric NOT NULL DEFAULT 0,
  discount numeric NOT NULL DEFAULT 0,
  total numeric NOT NULL DEFAULT 0,
  valid_until date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT estimates_pkey PRIMARY KEY (id),
  CONSTRAINT estimates_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id),
  CONSTRAINT estimates_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id),
  CONSTRAINT estimates_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id)
);
CREATE TABLE public.estimate_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL,
  title text NOT NULL,
  description text,
  unit text NOT NULL DEFAULT 'fixed'::text CHECK (unit = ANY (ARRAY['sqft'::text, 'room'::text, 'wall'::text, 'hour'::text, 'fixed'::text, 'item'::text, 'day'::text])),
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL DEFAULT 0,
  line_total numeric NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT estimate_items_pkey PRIMARY KEY (id),
  CONSTRAINT estimate_items_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id)
);
CREATE TABLE public.estimate_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  name text NOT NULL,
  service_type text,
  default_scope_text text,
  default_notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT estimate_templates_pkey PRIMARY KEY (id),
  CONSTRAINT estimate_templates_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.estimate_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT estimate_documents_pkey PRIMARY KEY (id),
  CONSTRAINT estimate_documents_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id)
);
CREATE TABLE public.ai_estimate_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  estimate_id uuid,
  admin_auth_id uuid NOT NULL,
  prompt text NOT NULL,
  response text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_estimate_logs_pkey PRIMARY KEY (id),
  CONSTRAINT ai_estimate_logs_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id),
  CONSTRAINT ai_estimate_logs_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.company_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL UNIQUE,
  company_name text NOT NULL,
  company_email text,
  company_phone text,
  company_website text,
  company_address text,
  tax_label text NOT NULL DEFAULT 'Tax'::text,
  default_tax_rate numeric NOT NULL DEFAULT 0.13,
  currency_code text NOT NULL DEFAULT 'CAD'::text,
  logo_path text,
  logo_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  country_code text NOT NULL DEFAULT 'CA'::text,
  region_code text NOT NULL DEFAULT 'QC'::text,
  timezone text NOT NULL DEFAULT 'America/Toronto'::text,
  enable_system_holidays boolean NOT NULL DEFAULT true,
  enable_construction_holiday boolean NOT NULL DEFAULT true,
  CONSTRAINT company_settings_pkey PRIMARY KEY (id),
  CONSTRAINT company_settings_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.estimate_email_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  estimate_id uuid NOT NULL,
  admin_auth_id uuid NOT NULL,
  recipient_email text NOT NULL,
  subject text NOT NULL,
  message_body text,
  pdf_document_id uuid,
  status text NOT NULL DEFAULT 'sent'::text CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])),
  provider_name text,
  provider_message_id text,
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  template_type text,
  CONSTRAINT estimate_email_logs_pkey PRIMARY KEY (id),
  CONSTRAINT estimate_email_logs_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id),
  CONSTRAINT estimate_email_logs_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id),
  CONSTRAINT estimate_email_logs_pdf_document_id_fkey FOREIGN KEY (pdf_document_id) REFERENCES public.estimate_documents(id)
);
CREATE TABLE public.invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  estimate_id uuid,
  client_id uuid NOT NULL,
  property_id uuid NOT NULL,
  invoice_number text NOT NULL,
  title text NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'partial'::text, 'paid'::text, 'overdue'::text, 'void'::text])),
  issue_date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date,
  notes text,
  terms text,
  payment_instructions text,
  subtotal numeric NOT NULL DEFAULT 0,
  tax numeric NOT NULL DEFAULT 0,
  discount numeric NOT NULL DEFAULT 0,
  total numeric NOT NULL DEFAULT 0,
  paid_amount numeric NOT NULL DEFAULT 0,
  balance_due numeric NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoices_pkey PRIMARY KEY (id),
  CONSTRAINT invoices_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id),
  CONSTRAINT invoices_estimate_id_fkey FOREIGN KEY (estimate_id) REFERENCES public.estimates(id),
  CONSTRAINT invoices_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id),
  CONSTRAINT invoices_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id)
);
CREATE TABLE public.invoice_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  title text NOT NULL,
  description text,
  unit text NOT NULL DEFAULT 'fixed'::text CHECK (unit = ANY (ARRAY['sqft'::text, 'room'::text, 'wall'::text, 'hour'::text, 'fixed'::text, 'item'::text, 'day'::text])),
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL DEFAULT 0,
  line_total numeric NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoice_items_pkey PRIMARY KEY (id),
  CONSTRAINT invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id)
);
CREATE TABLE public.invoice_payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  admin_auth_id uuid NOT NULL,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  payment_method text,
  reference_number text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoice_payments_pkey PRIMARY KEY (id),
  CONSTRAINT invoice_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id),
  CONSTRAINT invoice_payments_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.invoice_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoice_documents_pkey PRIMARY KEY (id),
  CONSTRAINT invoice_documents_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id)
);
CREATE TABLE public.invoice_email_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  admin_auth_id uuid NOT NULL,
  recipient_email text NOT NULL,
  subject text NOT NULL,
  message_body text,
  pdf_document_id uuid,
  status text NOT NULL DEFAULT 'sent'::text CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])),
  provider_name text,
  provider_message_id text,
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  template_type text,
  CONSTRAINT invoice_email_logs_pkey PRIMARY KEY (id),
  CONSTRAINT invoice_email_logs_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id),
  CONSTRAINT invoice_email_logs_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id),
  CONSTRAINT invoice_email_logs_pdf_document_id_fkey FOREIGN KEY (pdf_document_id) REFERENCES public.invoice_documents(id)
);
CREATE TABLE public.estimate_price_rules (
  id text NOT NULL,
  admin_auth_id uuid NOT NULL,
  service_type text NOT NULL,
  category text NOT NULL,
  unit text NOT NULL,
  base_rate numeric NOT NULL DEFAULT 0,
  material_rate_per_sqft numeric,
  material_fixed_rate numeric,
  prep_fixed_rate numeric,
  rush_fixed_rate numeric,
  single_coat_rate numeric,
  multi_coat_rate numeric,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  display_name text,
  aliases text[] NOT NULL DEFAULT '{}'::text[],
  ai_keywords text[] DEFAULT '{}'::text[],
  ai_scope_template text,
  ai_notes_template text,
  ai_labor_title text,
  ai_labor_description text,
  ai_materials_title text,
  ai_materials_description text,
  ai_prep_title text,
  ai_prep_description text,
  ai_rush_title text,
  ai_rush_description text,
  ai_followup_questions jsonb DEFAULT '[]'::jsonb,
  negative_keywords text[] NOT NULL DEFAULT '{}'::text[],
  install_fixed_rate numeric,
  replace_fixed_rate numeric,
  repair_fixed_rate numeric,
  diagnostic_fixed_rate numeric,
  icon_name text,
  CONSTRAINT estimate_price_rules_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_push_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_auth_id uuid NOT NULL,
  role text NOT NULL CHECK (role = ANY (ARRAY['admin'::text, 'worker'::text])),
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'android'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_push_tokens_pkey PRIMARY KEY (id)
);
CREATE TABLE public.worker_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_auth_id uuid NOT NULL,
  worker_id uuid NOT NULL,
  worker_auth_id uuid,
  title text NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  total_amount numeric DEFAULT 0,
  payment_method text DEFAULT 'Cash'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT worker_documents_pkey PRIMARY KEY (id),
  CONSTRAINT worker_documents_admin_auth_id_fkey FOREIGN KEY (admin_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.worker_time_off (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  worker_id uuid,
  worker_auth_id uuid NOT NULL,
  type text NOT NULL DEFAULT 'vacation'::text CHECK (type = ANY (ARRAY['vacation'::text, 'sick_leave'::text, 'personal'::text, 'unavailable'::text, 'company_closed'::text])),
  title text,
  reason text,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'cancelled'::text, 'completed'::text])),
  block_clock_in boolean NOT NULL DEFAULT true,
  notify_before_days integer NOT NULL DEFAULT 2,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT worker_time_off_pkey PRIMARY KEY (id),
  CONSTRAINT worker_time_off_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id),
  CONSTRAINT worker_time_off_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(id),
  CONSTRAINT worker_time_off_worker_auth_id_fkey FOREIGN KEY (worker_auth_id) REFERENCES auth.users(id)
);
CREATE TABLE public.system_holiday_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  country_code text NOT NULL,
  region_code text,
  title text NOT NULL,
  kind text NOT NULL DEFAULT 'system_holiday'::text CHECK (kind = ANY (ARRAY['system_holiday'::text, 'construction_holiday'::text])),
  rule_type text NOT NULL CHECK (rule_type = ANY (ARRAY['fixed_date'::text, 'nth_weekday'::text, 'last_weekday'::text, 'monday_before_date'::text, 'construction_holiday_qc'::text])),
  month integer,
  day integer,
  weekday integer,
  nth integer,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT system_holiday_rules_pkey PRIMARY KEY (id)
);

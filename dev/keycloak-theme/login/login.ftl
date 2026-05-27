<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=realm.password && realm.registrationAllowed && !registrationDisabled??; section>

    <#if section = "header">
    <#-- Brand header is rendered in the form section below -->

    <#elseif section = "form">
    <div class="industrial-mesh"></div>

    <#-- Header with locale selector -->
    <header class="fatto-header">
        <#if realm.internationalizationEnabled && locale.supported?size gt 1>
            <div class="locale-selector">
                <span class="material-symbols-outlined">language</span>
                <select onchange="if(this.value) window.location.href=this.value;" style="background:transparent;border:none;color:inherit;font:inherit;cursor:pointer;outline:none;appearance:none;-webkit-appearance:none;">
                    <#list locale.supported as l>
                        <option value="${l.url}" <#if l.label == locale.current>selected</#if>
                            style="background:#1e293b;color:#f1f5f9;">
                            ${l.label}
                        </option>
                    </#list>
                </select>
            </div>
        </#if>
    </header>

    <main class="fatto-main">
        <div class="glass-card">

            <#-- Brand -->
            <div class="brand-header">
                <div class="brand-logo-row">
                    <div class="brand-icon">
                        <svg fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
                            <path clip-rule="evenodd" d="M24 4H42V17.3333V30.6667H24V44H6V30.6667V17.3333H24V4Z" fill="currentColor" fill-rule="evenodd"></path>
                        </svg>
                    </div>
                    <h1 class="brand-name">FATTO</h1>
                </div>
                <h2 class="brand-subtitle">Enterprise Manufacturing ERP</h2>
                <p class="brand-tagline">${msg("loginAccountTitle")}</p>
            </div>

            <#-- Alert Messages -->
            <#if message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
                <div class="alert alert-${message.type}">
                    ${kcSanitize(message.summary)?no_esc}
                </div>
            </#if>

            <#-- Login Form -->
            <form class="fatto-form" action="${url.loginAction}" method="post">

                <div class="form-group">
                    <label for="username">
                        <#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if>
                    </label>
                    <div class="input-wrapper">
                        <input id="username"
                               name="username"
                               type="text"
                               value="${(login.username!'')}"
                               placeholder="user@fatto.corp"
                               autofocus
                               autocomplete="username" />
                        <span class="material-symbols-outlined input-icon">person</span>
                    </div>
                    <#if messagesPerField.existsError('username')>
                        <div class="alert alert-error" style="margin-top:0.5rem;margin-bottom:0;">
                            ${kcSanitize(messagesPerField.getFirstError('username'))?no_esc}
                        </div>
                    </#if>
                </div>

                <div class="form-group">
                    <div class="label-row">
                        <label for="password">${msg("password")}</label>
                        <#if realm.resetPasswordAllowed>
                            <a href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
                        </#if>
                    </div>
                    <div class="input-wrapper">
                        <input id="password"
                               name="password"
                               type="password"
                               placeholder="••••••••"
                               autocomplete="current-password" />
                        <span class="material-symbols-outlined input-icon">visibility</span>
                    </div>
                    <#if messagesPerField.existsError('password')>
                        <div class="alert alert-error" style="margin-top:0.5rem;margin-bottom:0;">
                            ${kcSanitize(messagesPerField.getFirstError('password'))?no_esc}
                        </div>
                    </#if>
                </div>

                <#if realm.rememberMe && !usernameHidden??>
                    <div style="display:flex;align-items:center;gap:0.5rem;">
                        <input id="rememberMe" name="rememberMe" type="checkbox"
                               <#if login.rememberMe??>checked</#if>
                               style="accent-color:var(--color-primary);width:16px;height:16px;cursor:pointer;" />
                        <label for="rememberMe" style="font-size:0.8125rem;color:var(--color-text-secondary);cursor:pointer;text-transform:none;letter-spacing:normal;font-weight:500;">
                            ${msg("rememberMe")}
                        </label>
                    </div>
                </#if>

                <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>

                <button class="btn-submit" type="submit" name="login" id="kc-login">
                    <span>${msg("doLogIn")}</span>
                    <span class="material-symbols-outlined">arrow_forward</span>
                </button>

            </form>

            <#-- Social / Identity Providers -->
            <#if realm.password && social?? && social.providers?has_content>
                <div class="social-section">
                    <p class="divider-text">${msg("identity-provider-login-label")}</p>
                    <#list social.providers as p>
                        <a class="btn-social" href="${p.loginUrl}" id="social-${p.alias}">
                            <#if p.iconClasses?has_content>
                                <i class="${p.iconClasses}" aria-hidden="true"></i>
                            </#if>
                            <span>${p.displayName!}</span>
                        </a>
                    </#list>
                </div>
            </#if>

        </div>
    </main>

    <#-- Footer -->
    <footer class="fatto-footer">
        <p class="copyright">&copy; 2026 FATTO Manufacturing Systems. All rights reserved.</p>
        <div class="footer-links">
            <a href="#">${msg("termsTitle")}</a>
            <a href="#">Privacy Policy</a>
            <a href="#">Support</a>
        </div>
    </footer>

    <#-- Blueprint Decoration -->
    <div class="blueprint-decoration">
        <svg fill="none" stroke="#2463eb" stroke-width="0.5" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
            <circle cx="100" cy="100" r="80"></circle>
            <circle cx="100" cy="100" r="60" stroke-dasharray="4 4"></circle>
            <line x1="20" x2="180" y1="100" y2="100"></line>
            <line x1="100" x2="100" y1="20" y2="180"></line>
            <rect height="80" transform="rotate(45 100 100)" width="80" x="60" y="60"></rect>
        </svg>
    </div>

    <#elseif section = "info">
        <#if realm.password && realm.registrationAllowed && !registrationDisabled??>
            <div style="text-align:center;margin-top:1rem;">
                <span style="color:var(--color-text-muted);font-size:0.8125rem;">
                    ${msg("noAccount")}
                    <a href="${url.registrationUrl}" style="font-weight:600;">${msg("doRegister")}</a>
                </span>
            </div>
        </#if>
    </#if>

</@layout.registrationLayout>

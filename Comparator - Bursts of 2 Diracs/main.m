ccc;

%%
%--------------------------------------------------------------------------
%----------------------------SET-UP----------------------------------------
%--------------------------------------------------------------------------
%For reconstruction of a stream of sufficiently separated Diracs, set K_B=1
%(i.e. one Dirac per burst)


% Parameters
t_int = 15;                    % Temporal interval where Diracs can be located is [0 t_int]
K     = 6;                     % Number of Diracs
K_B   = 2;                     % Number of Diracs in each burst
P = 1;                         % E-spline order
T_s   = 1 / 64;                % "continuous" time resolution
cad_it     = 5;                % Number of iterations for Cadzow algorithm
A = 1;                         % Amplitude of the sinusoidal test function of the comparator
f_tem = 1.76;                  % Frequency of comparator's test function
noise_var = 0.000001;           % Variance of input additive white Gaussian noise

% E-spline
omega_0 = -pi/3; 
lambda = -2*omega_0/3 ;

%%
%--------------------------------------------------------------------------
%----------------------CHANNEL 1-------------------------------------------
%--------------------------------------------------------------------------
m_1 = [0,3];
omega_m   = omega_0 + lambda * m_1;
alpha_vec1 = 1j * omega_m;
[phi1, t_phi1, L_phi1, h1, t_h1] = generate_e_spline(alpha_vec1, T_s, 1, 'anticausal');

%--------------------------------------------------------------------------
%----------------------CHANNEL 2-------------------------------------------
%--------------------------------------------------------------------------
m_2 = [1,2];
omega_m   = omega_0 + lambda * m_2;
alpha_vec2 = 1j * omega_m;
[phi2, t_phi2, L_phi2, h2, t_h2] = generate_e_spline(alpha_vec2, T_s, 1, 'anticausal');


%%
%--------------------------------------------------------------------------
%----------------------------INPUT ----------------------------------------
%--------------------------------------------------------------------------
% Stream of Diracs - input
t_sig = (0 : T_s : t_int)';
itk = [95 105  350 360  510 520];
t_k = t_sig(itk).';
a_k = [1  1  -0.5  -1  0.3  1.2 ]*0.5; %EXP 1

% Generate the continuous-time signal x(t)
x = zeros(size(t_sig));
x(itk(1:K)) = a_k(1:K);
[x_noisy, noise] = add_noise( x', noise_var);
% x = x_noisy';


%%
%--------------------------------------------------------------------------
%----------------------------OUTPUT----------------------------------------
%--------------------------------------------------------------------------

% For both channels, compute the continuous time signal y(t) = x(t) * h(t) and samples y[n]
%This is equivalent to the inner product between x and the E-spline phi
[y1, t_y1] = filter_input( x, h1, t_sig, t_h1, T_s ); % Channel 1
[y2, t_y2] = filter_input( x, h2, t_sig, t_h2, T_s ); % Channel 2

%%
%--------------------------------------------------------------------------
%--------------------------NON-UNIFORM SAMPLES-----------------------------
%--------------------------------------------------------------------------
% Find the time locations when the filtered input crosses the test funciton
n_vec1  = compare_filtered_input( A, f_tem, y1, t_y1, T_s ); % Channel 1
n_vec2  = compare_filtered_input( A, f_tem, y2, t_y2, T_s ); % Channel 2

% Output values at the non-uniform time shifts
y_n1 = y1(n_vec1'); % Channel 1
y_n2 = y2(n_vec2'); % Channel 2

% Copy the output samples to temporary vectors which we manipulate later
y_n1_temp = y_n1;
y_n2_temp = y_n2;

plot_all_signals( t_sig, x, t_y1, y1, t_y2, y2, A, f_tem, n_vec1', n_vec2', T_s, n_vec1*T_s, phi1, n_vec2*T_s, phi2, L_phi1, L_phi2);    

%%
%--------------------------------------------------------------------------
%--------------------------SEQUENTIAL ESTIMATION---------------------------
%--------------------------------------------------------------------------

%Start of observation window
%to ensure we have at least 2 overlapping kernels
t_end_previous_burst_1 = 0;
t_end_previous_burst_2 = 0;

%Initialize the estimated time locations t_est_k, and amplitudes a_est_k
t_est_k = [];
a_est_k = [];

%Set very small output samples to zero
y_n1_temp(abs(y_n1_temp)<0.01)=0;
y_n2_temp(abs(y_n2_temp)<0.01)=0;

while(~isempty(find(abs(y_n1_temp)>0)) && ~isempty(find(abs(y_n2_temp)>0))) %While we still have bursts to estimate (corresponding to non-zero output samples, stored in y_n1_temp and y_n2_temp respectively)
    t_est_curent_burst = [];
    a_est_curent_burst = [];

    %Find output samples corresponding to current burst
    [ y_n1_burst, n_vec1_burst, y_n1_temp] = find_burst_output_samples( y_n1_temp, y_n1, n_vec1);
    [ y_n2_burst, n_vec2_burst, y_n2_temp] = find_burst_output_samples( y_n2_temp, y_n2, n_vec2); 

    %Compute the signal moments for channel 1
    [s_m1, n_vec_d1, y_d1, disc_d1, c_m_n1] = compute_channel_moments(n_vec1_burst, L_phi1, y_n1_burst, P, alpha_vec1, phi1, t_phi1);
    %Compute the signal moments for channel 2
    [s_m2, n_vec_d2, y_d2, disc_d2, c_m_n2] = compute_channel_moments(n_vec2_burst, L_phi2, y_n2_burst, P, alpha_vec2, phi2, t_phi2);
    
    % Joint s_m
    s_m = [s_m1(1,1), s_m2(1,1), s_m2(2,1), s_m1(2,1)]';

    % Solve the system of equations using Prony's method
%     s_m = cadzow(s_m, 2, cad_it);

    S = toeplitz(s_m(K_B+1:end), s_m(K_B+1:-1:1));
    [~,~,V] = svd(S);
    h_prony       = V(:,end);
    uu_k    = roots(h_prony);
    angle_uu_k = sort(mod(angle(uu_k), 2*pi)) ;

    if (~isempty(angle_uu_k) && length(angle_uu_k)==2) % if we retrieve two solutions
        %Estimate the Diracs
        interval_start_time1 = (n_vec_d1(1,end)-L_phi1)*T_s;
        interval_start_time2 = (n_vec_d2(1,end)-L_phi2)*T_s;
        interval_start_time = max(interval_start_time1,interval_start_time2);
        interval_stop_time1 = (n_vec_d1(1,1))*T_s;
        interval_stop_time2 = (n_vec_d2(1,1))*T_s;
        interval_stop_time = min(interval_stop_time1,interval_stop_time2);
        [ tt_k1 ] = estimate_dirac( interval_start_time, interval_stop_time, angle_uu_k(1), lambda);  
        [ tt_k2 ] = estimate_dirac( interval_start_time, interval_stop_time, angle_uu_k(2), lambda);

        tt_k = [tt_k1, tt_k2];
        phi_mat = get_phi_tk_n_mat(phi1, t_phi1, tt_k, n_vec_d1, T_s);
        samples_aa_k = y_d1;
        aa_k    = real(phi_mat \ samples_aa_k); %estimated amplitude

        aa_k1 = aa_k(1,1);
        aa_k2 = aa_k(2,1);
        
        t_est_curent_burst = [tt_k1, tt_k2];
        a_est_curent_burst = [aa_k1, aa_k2];
        
        t_est_k = [t_est_k, t_est_curent_burst];
        a_est_k = [a_est_k, a_est_curent_burst];

    end
    
    %Plot exponential reproduction
%     plot_exp_recon( P, alpha_vec1, phi1, t_phi1, disc_d1, n_vec_d1, n_vec1, T_s, c_m_n1, t_k, a_k);  
%     plot_exp_recon( P, alpha_vec2, phi2, t_phi2, disc_d2, n_vec_d2, n_vec2, T_s, c_m_n2, t_k, a_k);      

end



%%
%--------------------------------------------------------------------------
%----------------------PLOT INPUT AND ESTIMATION---------------------------
%--------------------------------------------------------------------------
figure 
subplot(3,2,1)
stem(t_k(1:2),a_k(1:2), 'k^','fill','Markersize',3)
hold on
stem(t_k(3:4),a_k(3:4), 'kv','fill','Markersize',3)
stem(t_k(5:6),a_k(5:6), 'k^','fill','Markersize',3)
hold off;
xlabel('(a)');
title('Input signal');
axis([0 t_int -0.7 0.7]);


subplot(3,2,2)
stem(t_est_k(1:2),a_est_k(1:2), 'k^','fill','Markersize',3)
hold on
stem(t_est_k(3:4),a_est_k(3:4), 'kv','fill','Markersize',3)
stem(t_est_k(5:6),a_est_k(5:6), 'k^','fill','Markersize',3)
xlabel('(b)');
title('Reconstructed signal');
axis([0 t_int -0.7 0.7]);


subplot(3,2,3)
plot(t_phi1, phi1, 'k');
axis([-2.1 0.1 0 1]);
title('Channel 1 : sampling kernel');
xlabel('(c)');

subplot(3,2,4)
plot(t_phi2, phi2, 'k');
axis([-2.1 0.1 0 1]);
title('Channel 2 : sampling kernel');
xlabel('(d)');

subplot(3,2,5)
stem(n_vec1*T_s, y_n1, 'k','fill','Markersize',3);
xlabel('(e)');
title('Channel 1 : output samples');
axis([0 t_int -1 1]);

subplot(3,2,6)
stem(n_vec2*T_s, y_n2, 'k','fill','Markersize',3);
xlabel('(f)');
title('Channel 2 : output samples');
axis([0 t_int -1 1]);

error_t_est = immse(t_est_k, t_k);
error_a_est = immse(a_est_k, a_k);


<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AppointmentController;

Route::get('/appointments', [AppointmentController::class, 'index']);
Route::post('/appointments', [AppointmentController::class, 'store']);

Route::get('/appointments/{appointment}', [
    AppointmentController::class,
    'show',
]);

Route::post('/appointments/{appointment}/schedule', [
    AppointmentController::class,
    'schedule',
]);

Route::post('/appointments/{appointment}/cancel', [
    AppointmentController::class,
    'cancel',
]);

Route::post('/appointments/{appointment}/resolve-review', [
    AppointmentController::class,
    'resolveReview',
]);
